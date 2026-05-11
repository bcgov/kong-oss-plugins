local jwt_parser = require "kong.plugins.jwt.jwt_parser"
local cjson = require "cjson.safe"
local crypto = require "resty.openssl"
local digest = require "resty.openssl.digest"
local utils = require "kong.tools.utils"

local assert = assert
local rep = string.rep

local base64 = require "ngx.base64"

local resty_openssl = require "resty.openssl"
local pkey = require "resty.openssl.pkey"
local bn = require "resty.openssl.bn"
local json = require "cjson.safe"
local log = require("kong.plugins.plugin-log.log")
local kong = kong

local PLUGIN_NAME = "dpop"

local function base64_decode_url(input)
  local remainder = #input % 4

  if remainder > 0 then
    local padlen = 4 - remainder
    input = input .. rep("=", padlen)
  end

  return base64.decode_base64url(input)
end

local function send_error_response(status, error_code, description)
  kong.response.set_status(status)
  kong.response.set_header("Content-Type", "application/json")
  local body = {
    error = error_code,
    error_description = description
  }
  return log.exit_with_reason(
    {plugin = PLUGIN_NAME, reason = tostring(error_code) .. ": " .. tostring(description)},
    status,
    body
  )
end

local function extract_dpop_proof()
  local dpop_header = kong.request.get_header("DPoP")
  if not dpop_header then
    return nil, "DPoP header missing"
  end
  return dpop_header, nil
end

local function extract_access_token()
  local auth_header = kong.request.get_header("Authorization")
  if not auth_header then
    return nil, "Authorization header missing"
  end
  local token = auth_header:match("^DPoP%s+(.+)$") or auth_header:match("^Bearer%s+(.+)$")
  if not token then
    return nil, "Invalid Authorization header format"
  end
  return token, nil
end

local function create_canonical_jwk_json(jwk)
  local canonical = string.format('{"crv":"%s","kty":"%s","x":"%s","y":"%s"}', jwk.crv, jwk.kty, jwk.x, jwk.y)
  return canonical
end

local function calculate_jwk_thumbprint(jwk)
  if not jwk or type(jwk) ~= "table" then
    return nil, "Invalid JWK"
  end

  local json_str = nil
  if jwk.kty == "RSA" then
    canonical_jwk = {
      e = jwk.e,
      kty = jwk.kty,
      n = jwk.n
    }
  elseif jwk.kty == "EC" then
    json_str = create_canonical_jwk_json(jwk)
  elseif jwk.kty == "OKP" then
    canonical_jwk = {
      crv = jwk.crv,
      kty = jwk.kty,
      x = jwk.x
    }
  else
    return nil, "Unsupported key type: " .. tostring(jwk.kty)
  end

  local hash = digest.new("sha256")
  hash:update(json_str)
  local digest_bytes = hash:final()
  return base64.encode_base64url(digest_bytes), nil
end

local function ec_jwk_to_key(jwk)
  local x_bytes = base64_decode_url(jwk.x)
  local y_bytes = base64_decode_url(jwk.y)

  local curve_map = {
    ["P-256"] = "prime256v1",
    ["P-384"] = "secp384r1",
    ["P-521"] = "secp521r1"
  }

  local curve_name = curve_map[jwk.crv]
  if not curve_name then
    return nil, "Unsupported curve: " .. jwk.crv
  end

  local key,
    err =
    pkey.new(
    cjson.encode(jwk),
    {
      format = "JWK"
    }
  )
  if not key then
    return nil, "Failed to create EC public key: " .. tostring(err)
  end

  return key
end

local function jwk_to_pem(jwk)
  local pkey = require "resty.openssl.pkey"

  if jwk.kty == "RSA" then
    local rsa_params = {
      n = jwk.n,
      e = jwk.e
    }

    if rsa_params.n then
      rsa_params.n = base64_decode_url(rsa_params.n)
    end
    if rsa_params.e then
      rsa_params.e = base64_decode_url(rsa_params.e)
    end

    local key,
      err =
      pkey.new(
      {
        type = "RSA",
        bits = nil,
        rsa_n = rsa_params.n,
        rsa_e = rsa_params.e
      }
    )

    if not key then
      return nil, "Failed to create RSA public key: " .. tostring(err)
    end

    return key, nil
  elseif jwk.kty == "EC" then
    local ec_params = {
      curve = jwk.crv,
      x = jwk.x,
      y = jwk.y
    }

    if ec_params.x then
      ec_params.x = base64_decode_url(ec_params.x)
    end
    if ec_params.y then
      ec_params.y = base64_decode_url(ec_params.y)
    end

    local curve_name
    if ec_params.curve == "P-256" then
      curve_name = "prime256v1"
    elseif ec_params.curve == "P-384" then
      curve_name = "secp384r1"
    elseif ec_params.curve == "P-521" then
      curve_name = "secp521r1"
    else
      return nil, "Unsupported EC curve: " .. tostring(ec_params.curve)
    end

    local key,
      err =
      pkey.new(
      {
        type = "EC",
        curve = curve_name,
        ec_x = ec_params.x,
        ec_y = ec_params.y
      }
    )

    if not key then
      return nil, "Failed to create EC public key: " .. tostring(err)
    end

    return key, nil
  else
    return nil, "Unsupported key type: " .. tostring(jwk.kty)
  end
end

local function extract_public_key_from_header(header)
  if header.jwk then
    return ec_jwk_to_key(header.jwk)
  end
  if header.x5c and #header.x5c > 0 then
    return nil, "X.509 certificate processing not implemented"
  end
  return nil, "No supported public key format found in header"
end

local function validate_dpop_proof(dpop_proof, access_token, http_method, http_uri, config)
  local jwt_parts = utils.split(dpop_proof, ".")
  if #jwt_parts ~= 3 then
    return false, "Invalid JWT format"
  end

  local header_json = base64_decode_url(jwt_parts[1])
  if not header_json then
    return false, "Failed to decode JWT header"
  end

  local header = cjson.decode(header_json)
  if not header then
    return false, "Failed to parse JWT header JSON"
  end

  local payload_json = base64_decode_url(jwt_parts[2])
  if not payload_json then
    return false, "Failed to decode JWT payload"
  end

  local claims = cjson.decode(payload_json)
  if not claims then
    return false, "Failed to parse JWT payload JSON"
  end

  if header.typ ~= "dpop+jwt" then
    return false, "Invalid DPoP JWT type. Expected 'dpop+jwt', got: " .. tostring(header.typ)
  end

  local alg_valid = false
  for _, allowed_alg in ipairs(config.allowed_algorithms) do
    if header.alg == allowed_alg then
      alg_valid = true
      break
    end
  end
  if not alg_valid then
    return false, "Unsupported algorithm: " .. tostring(header.alg)
  end

  local public_key,
    err = extract_public_key_from_header(header)
  if not public_key then
    return false, err or "Failed to extract public key"
  end

  local signature = jwt_parts[3]
  local signature_bytes = base64_decode_url(signature)
  if not signature_bytes then
    return false, "Failed to decode JWT signature"
  end

  local signing_data = jwt_parts[1] .. "." .. jwt_parts[2]

  local verified = false
  if header.alg == "ES256" then
    assert(#signature_bytes == 64, "Signature must be 64 bytes.")
    verified,
      err = public_key:verify(signature_bytes, signing_data, "sha256", nil, {ecdsa_use_raw = true})
  else
    return false, "Unsupported signature algorithm: " .. header.alg
  end

  if not verified then
    return false, "DPoP proof signature verification failed"
  end

  if not claims.jti then
    return false, "Missing jti claim"
  end
  if not claims.htm or claims.htm ~= http_method then
    return false, "Invalid htm claim. Expected: " .. http_method .. ", got: " .. tostring(claims.htm)
  end
  if not claims.htu then
    return false, "Missing htu claim"
  end
  local expected_htu = http_uri:match("^([^%?#]*)")
  local provided_htu = claims.htu:match("^([^%?#]*)")
  if provided_htu ~= expected_htu then
    return false, "Invalid htu claim. Expected: " .. expected_htu .. ", got: " .. provided_htu
  end
  if not claims.iat then
    return false, "Missing iat claim"
  end
  local current_time = ngx.time()
  local iat = claims.iat
  if type(iat) ~= "number" then
    return false, "Invalid iat claim format"
  end
  if iat > current_time + config.clock_skew then
    return false, "DPoP proof issued in the future"
  end
  if current_time - iat > config.max_age then
    return false, "DPoP proof too old"
  end
  local cache_key = "dpop_jti:" .. claims.jti
  local cached_jti = kong.cache:get(cache_key)
  if cached_jti then
    return false, "DPoP proof replay detected"
  end

  local ttl = (config.max_age or 0) + (config.clock_skew or 0)
  if ttl > 0 then
    local ok, err = kong.cache:safe_add(cache_key, true, ttl)
    if not ok and err then
      kong.log.err("failed to store DPoP JTI in cache for replay protection: ", err)
    end
  end
  return true, nil, {
    public_key = public_key,
    jwk = header.jwk,
    jti = claims.jti,
    iat = claims.iat,
    claims = claims
  }
end

local function validate_token_binding(access_token, dpop_public_key)
  local token_jwt,
    err = jwt_parser:new(access_token)
  if err then
    return false, "Invalid access token format: " .. err
  end
  local claims = token_jwt.claims
  if not claims.cnf or not claims.cnf.jkt then
    return false, "Access token not bound to DPoP key (missing cnf.jkt claim)"
  end
  local dpop_thumbprint,
    err = calculate_jwk_thumbprint(dpop_public_key)
  if not dpop_thumbprint then
    return false, "Failed to calculate DPoP key thumbprint: " .. tostring(err)
  end

  if claims.cnf.jkt ~= dpop_thumbprint then
    return false, "DPoP key thumbprint mismatch"
  end
  return true, nil, {
    token_claims = claims,
    dpop_thumbprint = dpop_thumbprint
  }
end

local M = {}

function M.validate_dpop(config)
  local method = kong.request.get_method()
  local scheme = "https"
  local host = kong.request.get_host()
  local port = kong.request.get_port()
  local path = kong.request.get_path()
  local uri = scheme .. "://" .. host
  uri = uri .. path

  local dpop_proof,
    err = extract_dpop_proof()
  if not dpop_proof then
    if config.anonymous then
      kong.client.authenticate(nil, config.anonymous)
      log.continue_with_reason({plugin = PLUGIN_NAME, reason = "no proof; anonymous fallback"})
      return
    end
    return send_error_response(401, "invalid_request", err)
  end

  local access_token,
    err = extract_access_token()
  if not access_token then
    return send_error_response(401, "invalid_request", err)
  end

  local valid,
    err,
    dpop_data = validate_dpop_proof(dpop_proof, access_token, method, uri, config)
  if not valid then
    return send_error_response(401, "invalid_dpop_proof", err)
  end

  local bound,
    err,
    binding_data = validate_token_binding(access_token, dpop_data.jwk)
  if not bound then
    return send_error_response(401, "invalid_token", err)
  end

  kong.ctx.shared.dpop_validated = true
  kong.ctx.shared.access_token = access_token
  kong.ctx.shared.dpop_public_key = dpop_data.public_key
  kong.ctx.shared.dpop_claims = dpop_data.claims
  kong.ctx.shared.token_claims = binding_data.token_claims
  kong.ctx.shared.dpop_jti = dpop_data.jti

  -- local subject = binding_data.token_claims.sub
  -- if subject then
  --   kong.client.authenticate({id = subject}, nil)
  -- end

  kong.service.request.set_header("X-DPoP-Validated", "true")
  log.continue_with_reason({plugin = PLUGIN_NAME, reason = "DPoP proof validated"})
end

return M
