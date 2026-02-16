local pem2jwks = require("kong.plugins.trust-registry.pem_to_jwks")
local cjson = require "cjson"
local kong_meta = require "kong.meta"
local kong = kong

local TrustRegistryHandler = {
  PRIORITY = 940,
  VERSION = kong_meta.version
}

function TrustRegistryHandler:access(conf)
  local jwks_list = {}

  local key_list

  local params = kong.request.get_uri_captures()
  kong.log.warn("URI captures: ", cjson.encode(params))
  if params and params.named.key_set then
    kong.log.warn("Fetching keys for key set: ", params.named.key_set)
    local kset = kong.db.key_sets:select_by_name(params.named.key_set)
    if not kset then
      kong.log.err("Key set not found: ", conf.key_set)
      return kong.response.exit(404, {message = "Key set not found"})
    end
    key_list = kong.db.keys:each_for_set({id = kset.id})
  elseif conf.key_set then
    local kset = kong.db.key_sets:select_by_name(conf.key_set)
    if not kset then
      kong.log.err("Key set not found: ", conf.key_set)
      return kong.response.exit(404, {message = "Key set not found"})
    end
    key_list = kong.db.keys:each_for_set({id = kset.id})
  else
    key_list = kong.db.keys:each()
  end

  for key, err in key_list do
    if err then
      kong.log.err("Error fetching key: ", err)
      return
    end

    local kid = key.kid

    if key.jwk then
      -- If the key is already in JWK format, use it directly
      table.insert(jwks_list, cjson.decode(key.jwk))
    else
      local pem = key.pem.public_key

      local jwks_item,
        err = pem2jwks.public_key_to_jwks(pem, kid)

      if not jwks_item then
        kong.log.err("Error converting PEM to JWKS for key ID ", kid, ": ", err)
      else
        jwks_item.use = "sig"

        -- Add the JWKS item to the list
        table.insert(jwks_list, jwks_item)
      end
    end
  end

  -- Build the standard JWKS format
  local jwks_response = {
    keys = jwks_list
  }

  -- Return JSON response
  return kong.response.exit(
    200,
    jwks_response,
    {
      ["Content-Type"] = "application/json"
    }
  )
end

return TrustRegistryHandler
