local kong_meta = require "kong.meta"
local log = require("kong.plugins.plugin-log.log")
local x509 = require "resty.openssl.x509"
local set_header = kong.service.request.set_header
local clear_header = kong.service.request.clear_header

local PLUGIN_NAME = "mtls-auth"

local function is_empty(s)
    return s == nil or s == ''
end

-- Last matching subject attribute (CN/O). name:find starts at the beginning
-- unless last_pos is given, so iterate to keep the last occurrence.
local function last_attribute(name, nid)
    if not name then
        return nil
    end
    local value, pos
    while true do
        local obj, next_pos = name:find(nid, pos)
        if not obj then
            return value
        end
        value = obj.blob
        pos = next_pos
    end
end

-- CN/O from the verified cert's subject name (ASN.1), not the RFC 2253 DN
-- string, so RFC 4514 escapes (\, \XX) are not part of the stored value.
local function subject_cn_o()
    local pem = ngx.var.ssl_client_raw_cert
    if is_empty(pem) then
        local escaped = ngx.var.ssl_client_escaped_cert
        if not is_empty(escaped) then
            pem = ngx.unescape_uri(escaped)
        end
    end
    if is_empty(pem) then
        return nil, nil
    end

    local cert, err = x509.new(pem, "PEM")
    if not cert then
        kong.log.err(PLUGIN_NAME, ": failed to parse client certificate: ", err)
        return nil, nil
    end

    local subject = cert:get_subject_name()
    return last_attribute(subject, "CN"), last_attribute(subject, "O")
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

    local common_name, organization = subject_cn_o()

    -- Publish the verified certificate's attributes for downstream plugins
    -- (e.g. mtls-acl). kong.ctx.shared is per-request, in-worker memory, so
    -- unlike request headers it cannot be supplied or spoofed by the client.
    -- Keys with no source value (e.g. a subject without CN) are absent.
    kong.ctx.shared.mtls_auth = {
        cert = ngx.var.ssl_client_escaped_cert,
        fingerprint = ngx.var.ssl_client_fingerprint,
        serial = ngx.var.ssl_client_serial,
        issuer_dn = ngx.var.ssl_client_i_dn,
        subject_dn = ngx.var.ssl_client_s_dn,
        common_name = common_name,
        organization = organization,
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
        if common_name then
            set_header(config.upstream_cert_cn_header, common_name)
        else
            -- No CN on the certificate: clear rather than skip, so a
            -- client-supplied value on this header name can't survive.
            clear_header(config.upstream_cert_cn_header)
        end
    end

    if not is_empty(config.upstream_cert_org_header) then
        if organization then
            set_header(config.upstream_cert_org_header, organization)
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
