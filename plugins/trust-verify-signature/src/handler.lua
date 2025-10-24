local json = require("cjson")
local https = require("ssl.https")
local btoa = ngx.encode_base64
local kong_meta = require "kong.meta"
local kong = kong

local TrustVerifySignatureHandler = {
  PRIORITY = 710,
  VERSION = kong_meta.version
}

function TrustVerifySignatureHandler:access(conf)
  local request = kong.service.request

  if conf.direction == "request" then
    local headers = kong.request.get_headers()

    request.set_header("X-Trust-Verify-Signature-Req", "TBD")
  end
end

function TrustVerifySignatureHandler:header_filter(conf)
  if conf.direction == "response" then
    kong.log.warn("X-Trust-Verify-Signature-Res")
    local headers = kong.response.get_headers()
  end
end

return TrustVerifySignatureHandler
