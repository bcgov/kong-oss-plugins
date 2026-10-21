local pkey = require("resty.openssl.pkey")
local cjson = require("cjson")

local M = {}

function M.public_key_to_jwks(pem_string, key_id)
  -- Load the key
  local pubkey_pem,
    err = pkey.new(pem_string, {format = "PEM", type = "pu"})
  if not pubkey_pem then
    return nil, "Failed to load key: " .. err
  end

  local pubkey_jwk,
    err = pubkey_pem:tostring("public", "JWK")

  if not pubkey_jwk then
    return nil, "Failed to convert to JWK: " .. err
  end

  local jwk = cjson.decode(pubkey_jwk)
  jwk.kid = key_id
  return jwk, nil
end

return M
