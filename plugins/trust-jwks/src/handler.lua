-- handler.lua
local http = require "resty.http"
local jwt = require "resty.jwt"
local ssl = require "resty.openssl.ssl"
local x509 = require "resty.openssl.x509"
local x509_name = require "resty.openssl.x509.name"
local x509_extension = require "resty.openssl.x509.extension"
local cjson = require "cjson"
local base64 = require "ngx.base64"
local pem2jwks = require("kong.plugins.trust-registry.pem_to_jwks")
local jwt_decoder = require "kong.plugins.jwt.jwt_parser"

local function tm(message)
  kong.log.err("TS: ", os.clock(), " : ", message)
end

local errors = {
  invalid_jwks_uri = "invalid JWKS URI",
  fetch_failed = "failed to fetch JWKS",
  invalid_jwks = "invalid JWKS format",
  cert_validation_failed = "certificate validation failed",
  org_validation_failed = "organization validation failed",
  domain_validation_failed = "domain validation failed",
  jwt_verification_failed = "jwt verification failed"
}

local JWKValidatorHandler = {
  PRIORITY = 1000,
  VERSION = "1.0.0"
}

-- Custom HTTPS client that exposes certificate information
local function https_with_cert_info(url, options)
  options = options or {}
  local timeout = options.timeout or 10000

  -- Parse URL
  local scheme,
    host,
    port,
    path = url:match("^(https?)://([^:/]+):?(%d*)(.*)$")
  if not scheme then
    return nil, nil, "Invalid URL format"
  end

  if scheme ~= "https" then
    return nil, nil, "Only HTTPS URLs are supported"
  end

  port = port ~= "" and tonumber(port) or 443
  path = path ~= "" and path or "/"

  -- Create TCP socket
  local sock = ngx.socket.tcp()
  sock:settimeout(timeout)

  -- Connect
  local ok,
    err = sock:connect(host, port)
  if not ok then
    return nil, nil, "Connection failed: " .. err
  end

  -- Perform TLS handshake
  local session,
    err = sock:sslhandshake(nil, host, options.verify ~= false, false)
  if not session then
    sock:close()
    return nil, nil, "TLS handshake failed: " .. err
  end

  local sess = ssl.from_socket(sock)

  -- Extract certificate information
  local cert_info = {
    subject = {},
    san = {},
    issuer = {},
    valid_from = nil,
    valid_to = nil,
    serial = nil,
    is_ev = false,
    public_key = nil
  }

  -- -- Get peer certificate (PEM format)
  local cert,
    err = sess:get_peer_certificate()
  if not cert then
    sock:close()
    return nil, nil, "Failed to get peer certificate: " .. (err or "unknown")
  end

  -- Extract the public key
  local pubkey,
    err = cert:get_pubkey()
  if not pubkey then
    ngx.log(ngx.ERR, "Failed to get public key: ", err)
    return
  end
  cert_info.public_key = pubkey:to_PEM()

  -- Extract subject distinguished name
  local subject = cert:get_subject_name()
  if subject then
    -- Get Organization (O)
    local org = subject:find("O")
    if org then
      cert_info.subject.O = org.blob
    end

    -- Get Common Name (CN)
    local cn = subject:find("CN")
    if cn then
      cert_info.subject.CN = cn.blob
    end

    -- Get State/Province (ST)
    local st = subject:find("ST")
    if st then
      cert_info.subject.ST = st.blob
    end

    -- Get Country (C)
    local c = subject:find("C")
    if c then
      cert_info.subject.C = c.blob
    end

    -- Get Organizational Unit (OU)
    local ou = subject:find("OU")
    if ou then
      cert_info.subject.OU = ou.blob
    end
  end

  -- Extract issuer information
  local issuer = cert:get_issuer_name()
  if issuer then
    local issuer_cn = issuer:find("CN")
    if issuer_cn then
      cert_info.issuer.CN = issuer_cn.blob
    end

    local issuer_o = issuer:find("O")
    if issuer_o then
      cert_info.issuer.O = issuer_o.blob
    end
  end

  -- Extract Subject Alternative Names (SAN)
  local extensions = cert:get_extension("subjectAltName")
  if extensions then
    local san_data = extensions:text()
    -- Parse SAN entries (format: "DNS:example.com, DNS:*.example.com")
    for san_entry in san_data:gmatch("DNS:([^,%s]+)") do
      table.insert(cert_info.san, san_entry)
    end
    for san_entry in san_data:gmatch("IP Address:([^,%s]+)") do
      table.insert(cert_info.san, san_entry)
    end
  end

  -- Get validity period
  cert_info.valid_from = cert:get_not_before()
  cert_info.valid_to = cert:get_not_after()

  -- Get serial number
  local serial = cert:get_serial_number()
  if serial then
    cert_info.serial = serial:to_hex()
  end

  -- Check if it's an Extended Validation (EV) certificate
  local cert_policies = cert:get_extension("certificatePolicies")
  if cert_policies then
    local policy_text = cert_policies:text()
    -- Common EV OIDs
    local ev_oids = {
      "2.16.840.1.114028.10.1.2", -- DigiCert
      "2.16.578.1.26.1.3.3", -- Buypass
      "2.16.840.1.114412.2.1", -- DigiCert EV
      "1.3.6.1.4.1.34697.2.1", -- AffirmTrust
      "2.16.840.1.114413.1.7.23.3", -- GoDaddy
      "1.3.6.1.4.1.6449.1.2.1.5.1", -- Comodo
      "2.23.140.1.2.2" -- Sectigo
    }

    for _, oid in ipairs(ev_oids) do
      if policy_text:find(oid, 1, true) then
        cert_info.is_ev = true
        break
      end
    end
  end

  -- Send HTTP request over the established TLS connection
  local request =
    string.format(
    "GET %s HTTP/1.1\r\nHost: %s\r\nAccept: application/octet-stream\r\nUser-Agent: Kong-JWK-Validator/1.0\r\nConnection: close\r\n\r\n",
    path,
    host
  )

  local bytes,
    err = sock:send(request)
  if not bytes then
    sock:close()
    return nil, cert_info, "Failed to send request: " .. err
  end

  -- Read response
  local response = {}
  while true do
    local line,
      err,
      partial = sock:receive("*l")
    if not line then
      if partial then
        table.insert(response, partial)
      end
      break
    end
    table.insert(response, line)
  end

  sock:close()

  local response_text = table.concat(response, "\n")

  -- Parse HTTP response
  local status_line = response_text:match("^HTTP/[%d%.]+%s+(%d+)")
  local status_code = tonumber(status_line)

  -- Extract body (after double newline)
  local body = response_text:match("\r?\n\r?\n(.*)$")

  return {
    status = status_code,
    body = body
  }, cert_info, nil
end

-- Validate domain matches certificate
local function validate_domain(cert_info, expected_domain)
  if not expected_domain then
    return true
  end

  -- Check CN
  if cert_info.subject.CN then
    if cert_info.subject.CN == expected_domain then
      return true
    end
    -- Check wildcard CN (e.g., *.example.com matches api.example.com)
    if cert_info.subject.CN:match("^%*%.") then
      local base_domain = cert_info.subject.CN:gsub("^%*%.", "")
      if expected_domain:match("%." .. base_domain:gsub("%.", "%%.") .. "$") or expected_domain == base_domain then
        return true
      end
    end
  end

  -- Check SAN entries
  for _, san in ipairs(cert_info.san) do
    if san == expected_domain then
      return true
    end
    -- Check wildcard SAN
    if san:match("^%*%.") then
      local base_domain = san:gsub("^%*%.", "")
      if expected_domain:match("%." .. base_domain:gsub("%.", "%%.") .. "$") or expected_domain == base_domain then
        return true
      end
    end
  end

  return false
end

local function fetch_jwks_with_validation(jwks_uri, conf)
  -- Fetch with certificate extraction
  local response,
    cert_info,
    err =
    https_with_cert_info(
    jwks_uri,
    {
      timeout = conf.connect_timeout or 10000,
      verify = conf.verify_tls ~= false
    }
  )

  if err then
    return nil, err
  end

  if not cert_info then
    return nil, "Failed to extract certificate information"
  end

  -- Validate certificate is not expired
  local now = os.time()
  if cert_info.valid_from and now < cert_info.valid_from then
    return nil, "Certificate not yet valid"
  end
  if cert_info.valid_to and now > cert_info.valid_to then
    return nil, "Certificate has expired"
  end

  -- Additional validation: Check if EV cert is required
  if conf.require_ev and not cert_info.is_ev then
    return nil, "Extended Validation certificate required but not present"
  end

  -- Check HTTP response
  if not response or response.status ~= 200 then
    return nil, "JWKS fetch returned status: " .. (response and response.status or "unknown")
  end

  if not response.body then
    return nil, "Empty response body"
  end

  return {
    jwks = response.body,
    cert_info = cert_info
  }
end

-- Verify JWT and extract claims
local function verify_and_extract_jwt(public_key, token)
  local jwt_obj = jwt:verify(public_key, token)

  if not jwt_obj.verified then
    return nil, "JWT verification failed: " .. (jwt_obj.reason or "unknown")
  end

  return jwt_obj.payload
end

local function validate_organization(cert_info, expected_org, expected_domain)
  -- Validate organization binding
  if expected_org then
    if not cert_info.subject.O then
      return nil, "Certificate missing Organization field"
    end

    if cert_info.subject.O ~= expected_org then
      return nil, string.format(
        "Organization mismatch: cert has '%s', expected '%s'",
        cert_info.subject.O,
        expected_org
      )
    end
    kong.log.info("✓ Organization validated: " .. cert_info.subject.O)
  end

  -- Validate domain binding
  if expected_domain then
    if not validate_domain(cert_info, expected_domain) then
      return nil, string.format(
        "Domain mismatch: cert CN='%s', SANs=[%s], expected '%s'",
        cert_info.subject.CN or "none",
        table.concat(cert_info.san, ", "),
        expected_domain
      )
    end
    kong.log.info("✓ Domain validated: " .. expected_domain)
  end

  return false
end

local function trim(s)
  -- The pattern matches optional leading whitespace, captures everything in between,
  -- and matches optional trailing whitespace.
  return s:match("^%s*(.-)%s*$")
end

--
-- use the service url as the signed jwks uri
-- retrieve the signed jwks
-- gather TLS information from the connection
-- validate the TLS certificate against org/domain if provided
--
function JWKValidatorHandler:access(conf)
  local svc = kong.router.get_service()

  -- build service url
  local jwks_uri = "https://" .. svc.host .. ":" .. (svc.port or 443) .. svc.path

  local result,
    err = fetch_jwks_with_validation(jwks_uri, conf)

  if not result then
    kong.log.err("JWK validation failed: " .. err)
    return kong.response.exit(
      403,
      {
        message = "JWK validation failed",
        error = err
      }
    )
  end

  local signed_jwks = trim(result.jwks)
  local cert_info = result.cert_info

  local pub_jwk,
    err = pem2jwks.public_key_to_jwks(cert_info.public_key, "0")

  if not pub_jwk then
    kong.log.err("Error converting PEM to JWK: ", err)
    return kong.response.exit(
      403,
      {
        message = "Failed to convert public key to JWK"
      }
    )
  end

  -- kong.log.warn("Public JWK: ", cjson.encode(pub_jwk))
  -- kong.log.warn("Signed JWKS: ", signed_jwks)

  local jwks_jwt,
    err = jwt_decoder:new(signed_jwks)
  if err then
    return kong.response.exit(
      403,
      {
        message = "Bad token",
        error = err
      }
    )
  end

  local err = jwks_jwt:verify_signature(pub_jwk)
  if err then
    return kong.response.exit(
      403,
      {
        message = "Signature verification failed",
        error = tostring(err)
      }
    )
  end

  local jwks = jwks_jwt.claims
  local expected_org = jwks.org
  local expected_domain = jwks.org_domain

  local err = validate_organization(cert_info, expected_org, expected_domain)
  if err then
    kong.log.err("Organization/Domain validation failed: " .. err)
    return kong.response.exit(
      403,
      {
        message = "Organization/Domain validation failed",
        error = err
      }
    )
  end

  -- Store validated data in request context for downstream use
  kong.ctx.shared.validated_jwks = jwks
  kong.ctx.shared.cert_info = cert_info

  -- Add custom headers with validated information for upstream services
  kong.response.set_header("X-Validated-Org", cert_info.subject.O or "")
  kong.response.set_header("X-Validated-Domain", cert_info.subject.CN or "")
  kong.response.set_header("X-Cert-Serial", cert_info.serial or "")

  if cert_info.is_ev then
    kong.response.set_header("X-Cert-EV", "true")
  end

  -- Optionally add the full JWK as a header (be careful with size)
  if conf.add_cert_info then
    kong.log.inspect(cert_info)
    local cert_info_b64 = base64.encode_base64url(cjson.encode(cert_info))
    kong.response.set_header("X-Cert-Info", cert_info_b64)
  end

  kong.response.exit(200, jwks, {["Content-Type"] = "application/json"})
end

return JWKValidatorHandler
