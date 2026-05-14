local digest_mod = require("kong.plugins.trust-verify-digest.digest")
local https = require("ssl.https")
local btoa = ngx.encode_base64
local kong_meta = require "kong.meta"
local log = require("kong.plugins.plugin-log.log")
local kong = kong

local PLUGIN_NAME = "trust-verify-digest"

local function send_error_response(status, error_code, reason, description)
  kong.response.set_status(status)
  kong.response.set_header("Content-Type", "application/json")
  local body = {
    error = error_code,
    error_description = description
  }
  return log.exit_with_reason({plugin = PLUGIN_NAME, reason = reason}, status, body)
end

local TrustVerifyDigestHandler = {
  PRIORITY = 710,
  VERSION = kong_meta.version
}


function TrustVerifyDigestHandler:access(conf)
  local request = kong.service.request
  local response = kong.response

  if conf.direction == "request" then
    local body = kong.request.get_raw_body()
    if not body or body == "" then
      response.set_header("X-Trust-Verify-Digest-Status", "NoBody")
      return
    end

    local headers = kong.request.get_headers()
    local content_digest = headers["Content-Digest"]
    if not content_digest then
      response.set_header("X-Trust-Verify-Digest-Error", "Missing Content-Digest Header")
      return send_error_response(401, "invalid_content_digest", "request body present but Content-Digest header is missing")
    end

    local alg, digest_bytes, err = digest_mod.parse(content_digest)
    if err then
      kong.log.warn("Error parsing Content-Digest header: " .. err)
      response.set_header("X-Trust-Verify-Digest-Error", "Invalid Content-Digest Header")
      return send_error_response(401, "invalid_content_digest", "request Content-Digest header could not be parsed: " .. tostring(err))
    end

    local match = digest_mod.digest(body, alg)

    if digest_bytes ~= match then
      kong.log.warn("Digest Mismatch! Header: " .. str.to_hex(digest_bytes) .. " Computed: " .. str.to_hex(digest))
      response.set_header("X-Trust-Verify-Digest-Error", "Digest Mismatch")
      return send_error_response(401, "invalid_content_digest", "request Content-Digest does not match digest computed over the body")
    end
    response.set_header("X-Trust-Verify-Digest-Status", "Pass")
    log.continue_with_reason({plugin = PLUGIN_NAME, reason = "request digest matches"})
  end
end

function TrustVerifyDigestHandler:body_filter(conf)
  if conf.direction == "response" then
    kong.log.warn("X-Trust-Verify-Digest-Res")
    local body = kong.response.get_raw_body()
    if body == nil then
      kong.log.warn("Body is nil - no raw body available")
      return
    elseif body == "" then
      kong.log.warn("Body is empty string")
      return
    end 
    kong.log.warn("X-Trust-Verify-Digest-Res Body Length = ", #body)

    local headers = kong.response.get_headers()
    local content_digest = headers["Content-Digest"]
    if not content_digest then
      return send_error_response(401, "missing_content_digest", "upstream response is missing Content-Digest header")
    end

    local alg, digest_bytes, err = digest_mod.parse(content_digest)
    if err then
      kong.log.warn("Error parsing Content-Digest header: " .. err)
      kong.response.set_header("X-Trust-Verify-Digest-Error", "Invalid Content-Digest Header")
      return send_error_response(401, "invalid_content_digest", "upstream Content-Digest header could not be parsed: " .. tostring(err))
    end

    local match = digest_mod.digest(body, alg)

    if digest_bytes ~= match then
      kong.log.warn("Digest Mismatch! Header: " .. str.to_hex(digest_bytes) .. " Computed: " .. str.to_hex(digest))
      kong.response.set_header("X-Trust-Verify-Digest-Error", "Digest Mismatch")
      return send_error_response(401, "invalid_content_digest", "upstream Content-Digest does not match digest computed over the response body")
    end
    kong.response.set_header("X-Trust-Verify-Digest-Status", "Pass")
    log.continue_with_reason({plugin = PLUGIN_NAME, reason = "response digest matches"})
  end
end

return TrustVerifyDigestHandler
