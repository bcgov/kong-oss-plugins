local kong_meta = require "kong.meta"
local log = require("kong.plugins.plugin-log.log")
local set_header = kong.service.request.set_header
local clear_header = kong.service.request.clear_header

local PLUGIN_NAME = "mtls-auth"

-- utils
local function is_empty(s)
    return s == nil or s == ''
end

-- extract 'relative distinguished name' (which is a KEY=VALUE pair) from a 
-- distinguished name string, as given by start and end position
local function extract_and_add_rdn (t, dn, startPos, endPos)
	local delimiterPos, _ = string.find(dn, "=", startPos)
	if (delimiterPos)
	then
		local k = string.sub(dn, startPos, delimiterPos-1)
		local v = string.sub(dn, delimiterPos+1, endPos)
		t[k] = v
	end
end

-- parse a distinguished name string in rfc2253 format into map of 'relative distinguished names'
-- (i.e. KEY=VALUE pairs), allowing VALUEs to contain '\'-escaped comma characters
local function parse_dn (dn)
    local t={}
	local nextRdn = 1
	while(nextRdn <= #dn)
	do
		local endOfRdnPos, _ = string.find(dn, "[^\\],", nextRdn)
		if (endOfRdnPos == nil) then
			endOfRdnPos = #dn
		end
		extract_and_add_rdn (t, dn, nextRdn, endOfRdnPos)
		nextRdn = endOfRdnPos+2
	end
	return t
end

local MtlsAuth = {
  VERSION = kong_meta.version,
  PRIORITY = 975
}

function MtlsAuth:access(config)
    if ngx.var.ssl_client_verify ~= "SUCCESS" then
        log.exit_with_reason(
            {plugin = PLUGIN_NAME, reason = "ngx ssl_client_verify is '" .. tostring(ngx.var.ssl_client_verify) .. "', expected 'SUCCESS'; client certificate missing or invalid"},
            config.error_response_code,
            [[{"error":"invalid_request", "error_description": "mTLS client not provided or invalid"}]],
            {
                ["Content-Type"] = "application/json"
            }
        )
    end

    local cert_dn = parse_dn(ngx.var.ssl_client_s_dn)

    -- Publish the verified certificate's attributes for downstream plugins
    -- (e.g. mtls-acl). kong.ctx.shared is per-request, in-worker memory, so
    -- unlike request headers it cannot be supplied or spoofed by the client.
    -- Keys with no source value (e.g. a subject DN without CN) are absent.
    kong.ctx.shared.mtls_auth = {
        cert = ngx.var.ssl_client_escaped_cert,
        fingerprint = ngx.var.ssl_client_fingerprint,
        serial = ngx.var.ssl_client_serial,
        issuer_dn = ngx.var.ssl_client_i_dn,
        subject_dn = ngx.var.ssl_client_s_dn,
        common_name = cert_dn["CN"],
        organization = cert_dn["O"],
    }

    if not is_empty(config.upstream_cert_header) then
        set_header(config.upstream_cert_header, ngx.var.ssl_client_escaped_cert)
    end

    if not is_empty(config.upstream_cert_fingerprint_header) then
        set_header(config.upstream_cert_fingerprint_header, ngx.var.ssl_client_fingerprint)
    end

    if not is_empty(config.upstream_cert_serial_header) then
        set_header(config.upstream_cert_serial_header, ngx.var.ssl_client_serial)
    end

    if not is_empty(config.upstream_cert_i_dn_header) then
        set_header(config.upstream_cert_i_dn_header, ngx.var.ssl_client_i_dn)
    end

    if not is_empty(config.upstream_cert_s_dn_header) then
        set_header(config.upstream_cert_s_dn_header, ngx.var.ssl_client_s_dn)
    end

    if not is_empty(config.upstream_cert_cn_header) then
        if cert_dn["CN"] then
            set_header(config.upstream_cert_cn_header, cert_dn["CN"])
        else
            -- No CN on the certificate: clear rather than skip, so a
            -- client-supplied value on this header name can't survive.
            clear_header(config.upstream_cert_cn_header)
        end
    end

    if not is_empty(config.upstream_cert_org_header) then
        if cert_dn["O"] then
            set_header(config.upstream_cert_org_header, cert_dn["O"])
        else
            clear_header(config.upstream_cert_org_header)
        end
    end

    set_header("X-Tls-Server-Name", ngx.var.ssl_server_name)

    if ngx.var.ssl_client_verify then
        set_header("X-Tls-Client-Verify", ngx.var.ssl_client_verify)
    end

    log.continue_with_reason({plugin = PLUGIN_NAME, reason = "client certificate verified"})
end

return MtlsAuth
