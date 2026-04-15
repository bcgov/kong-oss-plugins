-- pem_to_jwk.lua: trust-registry-ai
-- FR-006: Convert PEM-encoded public keys to JWK format (RSA and EC).
local openssl_pkey = require "resty.openssl.pkey"
local ngx = ngx

local M = {}

-- Map OpenSSL curve short names to JWK "crv" values (RFC 7518)
local CURVE_MAP = {
  ["prime256v1"] = "P-256",
  ["secp256r1"]  = "P-256",
  ["secp384r1"]  = "P-384",
  ["secp521r1"]  = "P-521",
}

-- Encode a binary string as base64url without padding (RFC 7517 §2)
local function b64url(s)
  return ngx.encode_base64(s)
    :gsub("+", "-")
    :gsub("/", "_")
    :gsub("=+$", "")
end

-- Convert a PEM-encoded public key to a JWK table.
-- @param pem_string  string  PEM-encoded public key
-- @param kid         string  Key identifier (maps to "kid" in JWK)
-- @return table JWK object, or nil and an error string
function M.pem_to_jwk(pem_string, kid)
  local pkey, err = openssl_pkey.new(pem_string)
  if not pkey then
    return nil, "failed to load PEM key: " .. tostring(err)
  end

  local params, perr = pkey:get_parameters()
  if not params then
    return nil, "failed to get key parameters: " .. tostring(perr)
  end

  -- RSA: n and e parameters are present
  if params.n and params.e then
    return {
      kty = "RSA",
      kid = kid,
      n   = b64url(params.n:to_binary()),
      e   = b64url(params.e:to_binary()),
    }, nil
  end

  -- EC: x and y coordinates are present
  if params.x and params.y then
    local key_type = pkey:get_key_type()
    local crv

    -- Determine curve name from key type metadata
    if key_type and key_type.bits then
      if key_type.bits == 256 then
        crv = "P-256"
      elseif key_type.bits == 384 then
        crv = "P-384"
      elseif key_type.bits == 521 then
        crv = "P-521"
      end
    end

    -- Refine with explicit curve name if available
    if key_type and key_type.sn then
      crv = CURVE_MAP[key_type.sn] or crv
    end

    return {
      kty = "EC",
      kid = kid,
      crv = crv or "unknown",
      x   = b64url(params.x:to_binary()),
      y   = b64url(params.y:to_binary()),
    }, nil
  end

  local key_type = pkey:get_key_type()
  return nil, "unsupported key type: " .. tostring(key_type and key_type.sn or "unknown")
end

return M
