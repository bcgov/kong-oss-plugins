local digest_mod = require("kong.plugins.trust-verify-digest.digest")
local https = require("ssl.https")
local btoa = ngx.encode_base64
local kong_meta = require "kong.meta"
local kong = kong

local function send_error_response(status, error_code, description)
  kong.response.set_status(status)
  kong.response.set_header("Content-Type", "application/json")
  local body = {
    error = error_code,
    error_description = description
  }
  return kong.response.exit(status, body)
end

local TrustVerifyDigestHandler = {
  PRIORITY = 710,
  VERSION = kong_meta.version
}


function TrustVerifyDigestHandler:access(conf)
  local request = kong.service.request

  if conf.direction == "request" then
    local body = kong.request.get_raw_body()
    if not body or body == "" then
      request.set_header("X-Trust-Verify-Digest-Error", "Empty Body")
      return
    end

    local headers = kong.request.get_headers()
    local content_digest = headers["Content-Digest"]
    if not content_digest then
      request.set_header("X-Trust-Verify-Digest-Error", "Missing Content-Digest Header")
      return
    end

    request.set_header("X-Trust-Verify-Digest", "TBD")

    local calc_digest = digest.digest(body, "sha256")

    -- Here you would add the logic to verify the digest against the body
    -- For demonstration, we will just log the content digest
    kong.log.warn("Verifying Content-Digest: " .. content_digest)
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
      return
    end

    local alg, digest_bytes, err = digest_mod.parse(content_digest)
    if err then
      kong.log.warn("Error parsing Content-Digest header: " .. err)
      kong.response.set_header("X-Trust-Verify-Digest-Error", "Invalid Content-Digest Header")
      return send_error_response(401, "invalid_content_digest")
    end

    local match = digest_mod.digest(body, alg)

    assert(digest_bytes == match)
    
    if digest_bytes ~= match then
      kong.log.warn("Digest Mismatch! Header: " .. str.to_hex(digest_bytes) .. " Computed: " .. str.to_hex(digest))
      kong.response.set_header("X-Trust-Verify-Digest-Error", "Digest Mismatch")
      return send_error_response(401, "invalid_content_digest")
    end
    kong.response.set_header("X-Trust-Verify-Digest-Status", "Pass")
  end
end

return TrustVerifyDigestHandler
