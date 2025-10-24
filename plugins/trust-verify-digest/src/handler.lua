local json = require("cjson")
local https = require("ssl.https")
local btoa = ngx.encode_base64
local kong_meta = require "kong.meta"
local kong = kong

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

    -- Here you would add the logic to verify the digest against the body
    -- For demonstration, we will just log the content digest
    kong.log.warn("Verifying Content-Digest: " .. content_digest)
  end
end

return TrustVerifyDigestHandler
