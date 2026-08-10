local kong_meta = require "kong.meta"
local log = require("kong.plugins.plugin-log.log")
local clear_header = kong.service.request.clear_header

local PLUGIN_NAME = "mtls-acl"

-- kong.request.get_headers() normalizes header name case and dash/underscore
-- equivalence for us, and raising the limit to the PDK's maximum avoids
-- silently dropping the configured header on requests with many headers.
local MAX_HEADERS = 1000

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

-- Returns the header value and a boolean indicating whether the header was
-- sent more than once (kong.request.get_headers() returns a table of values
-- in that case, rather than a single string).
local function get_header_value(header_name)
    local v = kong.request.get_headers(MAX_HEADERS)[header_name]
    if type(v) == "table" then
        return nil, true
    end
    return v, false
end

local MtlsAcl = {
  VERSION = kong_meta.version,
  PRIORITY = 950
}


function MtlsAcl:access(plugin_conf)
    local certificate, duplicated = get_header_value(plugin_conf.certificate_header_name)
    if duplicated then
        return log.exit_with_reason(
            {plugin = PLUGIN_NAME, reason = "certificate header sent more than once"},
            403,
            {
                message = "You cannot consume this service"
            }
        )
    end
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