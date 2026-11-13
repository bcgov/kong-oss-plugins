local jwks = require "kong.plugins.trust-registry.jwks"
local kong_meta = require "kong.meta"
local log = require "kong.plugins.plugin-log.log"
local kong = kong

local TrustRegistryHandler = {
  PRIORITY = 940,
  VERSION = kong_meta.version
}

function TrustRegistryHandler:access(conf)
  local captures = kong.request.get_uri_captures()
  local name = captures and captures.named and captures.named.key_set or conf.key_set
  local body, status, err = jwks.build(kong.db.keys, kong.db.key_sets, name)
  if status == 500 then
    kong.log.err("trust-registry: registry read failed: ", err)
    body = {message = "Internal server error"}
  elseif status == 404 then
    body = {message = "Key set not found"}
  end
  return log.exit_with_reason(
    {plugin = "trust-registry", reason = status == 200 and "returning public JWKS document" or "registry lookup failed"},
    status, body, {["Content-Type"] = "application/json"}
  )
end

return TrustRegistryHandler
