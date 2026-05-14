local kong_meta = require "kong.meta"
local log = require("kong.plugins.plugin-log.log")
local clear_header = kong.service.request.clear_header

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

local function get_header_value(header_name)
    local h = ngx.req.get_headers()
    for k, v in pairs(h) do
        if string.lower(k) == string.lower(header_name) then
            return v
        end
    end
    return nil
end

local MtlsAcl = {
  VERSION = kong_meta.version,
  PRIORITY = 950
}


function MtlsAcl:access(plugin_conf)
    local certificate = get_header_value(plugin_conf.certificate_header_name)
    if not is_empty(certificate) then
		if not is_empty(plugin_conf.allow) then
		    if contains(plugin_conf.allow, certificate) then
				if (plugin_conf.hide_certificate_header) then
					clear_header(plugin_conf.certificate_header_name)
				end
		        log.continue_with_reason({plugin = PLUGIN_NAME, reason = "certificate allowed"})
		        return
			end
		end
		if not is_empty(plugin_conf.deny) then
		    if not contains(plugin_conf.deny, certificate) then
				if (plugin_conf.hide_certificate_header) then
					clear_header(plugin_conf.certificate_header_name)
				end
		        log.continue_with_reason({plugin = PLUGIN_NAME, reason = "certificate not denied"})
		        return
			end
		end
	end
    return log.exit_with_reason(
        {plugin = PLUGIN_NAME, reason = "client certificate is missing or did not satisfy the configured allow/deny rules"},
        403,
        {
            message = "You cannot consume this service"
        }
    )

end

return MtlsAcl