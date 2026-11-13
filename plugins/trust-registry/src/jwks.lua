local cjson = require "cjson.safe"
local pem = require "kong.plugins.trust-registry.pem_to_jwks"

local M = {}
local parameters = {
  RSA = {"n", "e"},
  EC = {"crv", "x", "y"},
  OKP = {"crv", "x"},
}
local metadata = {"kid", "use", "alg", "key_ops", "x5u", "x5c", "x5t", "x5t#S256"}

local function public_jwk(key)
  local jwk
  if key.jwk and key.jwk ~= ngx.null then
    jwk = cjson.decode(key.jwk)
  elseif type(key.pem) == "table" and type(key.pem.public_key) == "string" then
    jwk = pem.public_key_to_jwks(key.pem.public_key, key.kid)
    if jwk then jwk.use = "sig" end
  end
  if type(jwk) ~= "table" then return nil end
  local fields = parameters[jwk.kty]
  if not fields then return nil end
  local result = {kty = jwk.kty}
  for _, field in ipairs(fields) do
    if type(jwk[field]) ~= "string" or jwk[field] == "" then return nil end
    result[field] = jwk[field]
  end
  for _, field in ipairs(metadata) do result[field] = jwk[field] end
  return result
end

-- DAO injection keeps persistence faults testable without mocking the handler/PDK.
function M.build(keys, keysets, name)
  local iterator
  if name then
    local set, err = keysets:select_by_name(name)
    if err then return {message = "Internal server error"}, 500, err end
    if not set then return {message = "Key set not found"}, 404 end
    iterator = keys:each_for_set({id = set.id})
  else
    iterator = keys:each()
  end
  local result = setmetatable({}, cjson.array_mt)
  while true do
    local key, err = iterator()
    if err then return {message = "Internal server error"}, 500, err end
    if not key then break end
    local item = public_jwk(key)
    if item then result[#result + 1] = item end
  end
  return {keys = result}, 200
end

return M
