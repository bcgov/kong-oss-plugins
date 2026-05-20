local cjson = require "cjson"
local kong_meta = require "kong.meta"
local jwks = require "kong.plugins.trust-registry-ai-openspec.jwks"

local TrustRegistryAiOpenspecHandler = {
  PRIORITY = 950,
  VERSION = kong_meta.version
}

function TrustRegistryAiOpenspecHandler:access(conf)
  local path = kong.request.get_path()

  local key_set_name
  local m = ngx.re.match(path, [[^/keysets/(.+)/.well-known/jwks\.json$]], "jo")
  if m then
    key_set_name = m[1]
  end

  local body, status, err = jwks.build_jwks(key_set_name)
  if err then
    if status == 404 then
      return kong.response.exit(404, { message = err })
    end
    return kong.response.exit(500, { message = err })
  end

  return kong.response.exit(status, cjson.encode(body), {
    ["Content-Type"] = "application/json"
  })
end

return TrustRegistryAiOpenspecHandler
