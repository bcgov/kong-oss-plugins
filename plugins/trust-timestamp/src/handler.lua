local json = require("cjson")
local https = require("ssl.https")
local btoa = ngx.encode_base64
local kong_meta = require "kong.meta"
local kong = kong

local TrustTimestampHandler = {
  PRIORITY = 620,
  VERSION = kong_meta.version
}

local digest = require("resty.openssl.digest")
local bn = require("resty.openssl.bn")
local asn1 = require("resty.openssl.asn1")
local https = require("ssl.https")
local ltn12 = require("ltn12")

-- Manual ASN.1 DER encoding helpers
local function der_encode_length(len)
    if len < 128 then
        return string.char(len)
    else
        local bytes = {}
        while len > 0 do
            table.insert(bytes, 1, string.char(len % 256))
            len = math.floor(len / 256)
        end
        return string.char(0x80 + #bytes) .. table.concat(bytes)
    end
end

local function der_sequence(...)
    local content = table.concat({...})
    return string.char(0x30) .. der_encode_length(#content) .. content
end

local function der_integer(data)
    -- Ensure positive integer with padding if needed
    if data:byte(1) >= 0x80 then
        data = "\x00" .. data
    end
    return string.char(0x02) .. der_encode_length(#data) .. data
end

local function der_octet_string(data)
    return string.char(0x04) .. der_encode_length(#data) .. data
end

local function der_oid(oid_bytes)
    return string.char(0x06) .. der_encode_length(#oid_bytes) .. oid_bytes
end

local function der_boolean(val)
    return string.char(0x01, 0x01, val and 0xFF or 0x00)
end

function create_timestamp_query(data)
    -- Step 1: Create SHA-512 hash
    local d = digest.new("sha512")
    d:update(data)
    local hash = d:final()
    
    -- Step 2: Generate nonce (64-bit random)
    local nonce_bn = bn.new()
    nonce_bn = bn.generate_prime(64)  -- or use random
    local nonce_bytes = nonce_bn:to_binary()
    
    -- Step 3: Build TSQ manually
    -- SHA-512 OID: 2.16.840.1.101.3.4.2.3
    local sha512_oid = "\x60\x86\x48\x01\x65\x03\x04\x02\x03"

    -- AlgorithmIdentifier for SHA-512
    local algorithm_id = der_sequence(
        der_oid(sha512_oid),
        string.char(0x05, 0x00)  -- NULL
    )
    
    -- MessageImprint
    local message_imprint = der_sequence(
        algorithm_id,
        der_octet_string(hash)
    )
    
    -- Version (INTEGER 1)
    local version = der_integer("\x01")
    
    -- Nonce (INTEGER)
    local nonce = der_integer(nonce_bytes)
    
    -- CertReq (BOOLEAN TRUE) - NOT wrapped in [0]
    local cert_req = der_boolean(true)
    
    -- TimeStampReq SEQUENCE
    local tsq_der = der_sequence(
        version,
        message_imprint,
        nonce,
        cert_req
    )
    
    return tsq_der, nonce_bytes
end

--[[

  Example:
    {
      "artifactHash": "5JqJeqxMmBkhJwo/eeRohcmVL8W6GrTAze84C+dzdIE=",
      "certificates": true,
      "hashAlgorithm": "sha256",
      "nonce": 1123343434,
      "tsaPolicyOID": "1.2.3.4"
    }
]]
local function call_ts_authority(tsa_url, policy_oid, artifact)
  local tsq_der, nonce = create_timestamp_query(artifact)
  local response_body = {}
  local res,
    status_code,
    headers,
    status_line =
    https.request {
    url = tsa_url,
    method = "POST",
    headers = {
      ["Content-Type"] = "application/timestamp-query",
      ["Content-Length"] = tostring(#tsq_der)
    },
    source = ltn12.source.string(tsq_der),
    sink = ltn12.sink.table(response_body)
  }

  kong.log.warn("Timestamp Authority response code: ", status_code)
  if status_code ~= 200 then
    kong.log.err("Timestamp Authority error: ", table.concat(response_body))
    return nil
  end
  if res then
    return tsq_der, table.concat(response_body)
  end
end

--[[
  Calls a timestamp authority to get a trusted timestamp for a given artifact.
  The trusted timestamp can be used to prove that the artifact existed at a specific point in time.
  The plugin adds the trusted timestamp to the response headers for downstream verification.
]]
function TrustTimestampHandler:header_filter(conf)
  if kong.response.get_source() ~= "service" then
    return
  end

  local artifact = kong.response.get_header("Signature")
  local tsq_der, tsr_der = call_ts_authority(conf.endpoint_url, conf.policy_oid, artifact)

  if tsq_der == nil or tsr_der == nil then
    kong.log.err("Failed to obtain trusted timestamp from authority")
    kong.response.set_header("X-Trust-Timestamp-Error", "Failed to obtain trusted timestamp")
    return
  end

  kong.response.set_header("X-Trust-Timestamp-Tsq", btoa(tsq_der))
  kong.response.set_header("X-Trust-Timestamp", btoa(tsr_der))

  kong.ctx.shared.rfc3161_artifact = btoa(tsr_der)
end

return TrustTimestampHandler
