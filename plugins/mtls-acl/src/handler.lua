local kong_meta = require "kong.meta"
local log = require("kong.plugins.plugin-log.log")
local clear_header = kong.service.request.clear_header

local PLUGIN_NAME = "mtls-acl"

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

-- '-' and '_' are treated as equivalent, mirroring how nginx variables and
-- CGI-style upstreams normalize header names, so name variants cannot smuggle
-- a second value past the duplicate check or the hide feature.
local function normalize_header_name(name)
    return (string.gsub(string.lower(name), "_", "-"))
end

-- Returns the certificate header's value, a boolean indicating whether the
-- header appeared more than once (repeated exact name, or under a case or
-- '-'/'_' name variant), and the name form the client actually sent.
local function get_header_value(header_name)
    local canonical = normalize_header_name(header_name)
    local value, matched_name
    local matches = 0
    local duplicated = false
    for name, v in pairs(kong.request.get_headers(MAX_HEADERS)) do
        if normalize_header_name(name) == canonical then
            matches = matches + 1
            matched_name = name
            if type(v) == "table" then
                duplicated = true
            else
                value = v
            end
        end
    end
    return value, duplicated or matches > 1, matched_name
end

local MtlsAcl = {
  VERSION = kong_meta.version,
  PRIORITY = 950
}


function MtlsAcl:access(plugin_conf)
    local certificate, duplicated, matched_name = get_header_value(plugin_conf.certificate_header_name)
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
					clear_header(matched_name)
				end
		        log.continue_with_reason({plugin = PLUGIN_NAME, reason = "certificate allowed"})
		        return
			end
		end
		if not is_empty(plugin_conf.deny) then
		    if not contains(plugin_conf.deny, certificate) then
				if (plugin_conf.hide_certificate_header) then
					clear_header(matched_name)
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