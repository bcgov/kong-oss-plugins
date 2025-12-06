local json = require("cjson")
local https = require("ssl.https")
local jwt_decoder = require "kong.plugins.jwt.jwt_parser"
local signature = require("kong.plugins.trust-verify-signature.signature")
local btoa = ngx.encode_base64
local kong_meta = require "kong.meta"
local kong = kong

local TrustVerifySignatureHandler = {
  PRIORITY = 710,
  VERSION = kong_meta.version
}

local function verify_jwt_signature(conf, token)
  local jwt,
    err = jwt_decoder:new(token)
  if err then
    return false, {status = 401, message = "Bad token; " .. tostring(err)}
  end

  if conf.manifest_type == "signature-only" then
    -- no additional checks
  elseif conf.manifest_type == "content-digest" then
    local payload = jwt.claims
    if not payload or not payload["cd"] then
      return false, {status = 401, message = "Signature missing content digest manifest (cd)"}
    end

    if kong.service.request.get_header("Content-Digest") ~= payload["cd"] then
      return false, {status = 401, message = "Content-Digest header does not match signature manifest"}
    end
  end

  return signature.verify_jwt_signature(conf, jwt)
end

function TrustVerifySignatureHandler:access(conf)
  local request = kong.service.request

  if conf.direction == "request" then
    local headers = kong.request.get_headers()

    local sig = headers[conf.signature_header_key]
    if not sig then
      return kong.response.exit(401, {message = "Missing Signature in " .. conf.signature_header_key})
    end

    local ok,
      err = verify_jwt_signature(conf, sig)

    if not ok then
      return kong.response.exit(err.status, {message = err.message})
    end

    request.set_header("X-Trust-Verify-Signature-Req", "OK")
  end
end

function TrustVerifySignatureHandler:header_filter(conf)
  if conf.direction == "response" then
    kong.log.warn("X-Trust-Verify-Signature-Res")
    local headers = kong.response.get_headers()

    local sig = headers[conf.signature_header_key]
    if not sig then
      return kong.response.exit(401, {message = "Missing Signature in " .. conf.signature_header_key})
    end

    local ok,
      err = verify_jwt_signature(conf, sig)

    if not ok then
      return kong.response.exit(err.status, {message = err.message})
    end

    request.set_header("X-Trust-Verify-Signature-Res", "OK")
  end
end

return TrustVerifySignatureHandler
