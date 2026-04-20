-- pem_to_jwk.lua: trust-registry-ai
-- FR-006: Convert PEM-encoded public keys to JWK format.
-- FR-012: Delegate JWK serialization to resty.openssl.pkey's native
-- "JWK" output mode, which supports every key type OpenSSL exposes
-- (RSA, EC, and future additions such as Ed25519/Ed448).
local openssl_pkey = require "resty.openssl.pkey"
local cjson        = require "cjson"

local M = {}

-- Convert a PEM-encoded public key to a JWK table.
-- @param pem_string  string  PEM-encoded public key
-- @param kid         string  Key identifier (maps to "kid" in JWK)
-- @return table JWK object, or nil and an error string
function M.pem_to_jwk(pem_string, kid)
  local pkey, err = openssl_pkey.new(pem_string)
  if not pkey then
    return nil, "failed to load PEM key: " .. tostring(err)
  end

  local jwk_json, jerr = pkey:tostring("public", "JWK")
  if not jwk_json then
    return nil, "failed to serialize key as JWK: " .. tostring(jerr)
  end

  local ok, jwk = pcall(cjson.decode, jwk_json)
  if not ok or type(jwk) ~= "table" then
    return nil, "failed to decode JWK JSON: " .. tostring(jwk)
  end

  jwk.kid = kid
  return jwk, nil
end

return M
