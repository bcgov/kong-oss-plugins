local kong_meta = require "kong.meta"
local log = require("kong.plugins.plugin-log.log")

local PLUGIN_NAME = "mtls-acl"

-- utils
local function is_empty(s)
    return s == nil or s == ''
end

local function contains (tab, val)
    for _, value in ipairs(tab) do
        if value == val then
            return true
        end
    end
    return false
end

local MtlsAcl = {
  VERSION = kong_meta.version,
  PRIORITY = 950
}


function MtlsAcl:access(plugin_conf)
    -- The authorization subject comes exclusively from the shared per-request
    -- context populated by a trusted preceding plugin (normally mtls-auth).
    -- Request content plays no part, so a client cannot supply, duplicate, or
    -- spoof the value the way it could a request header.
    local mtls = kong.ctx.shared.mtls_auth
    local certificate = mtls and mtls[plugin_conf.certificate_attribute]

    if not is_empty(certificate) then
        if not is_empty(plugin_conf.allow) then
            if contains(plugin_conf.allow, certificate) then
                log.continue_with_reason({plugin = PLUGIN_NAME, reason = "certificate allowed"})
                return
            end
        end
        if not is_empty(plugin_conf.deny) then
            if not contains(plugin_conf.deny, certificate) then
                log.continue_with_reason({plugin = PLUGIN_NAME, reason = "certificate not denied"})
                return
            end
        end
    end
    return log.exit_with_reason(
        {plugin = PLUGIN_NAME, reason = "certificate attribute is missing from the shared mtls-auth context or did not satisfy the configured allow/deny rules"},
        403,
        {
            message = "You cannot consume this service"
        }
    )

end

return MtlsAcl
