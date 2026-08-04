local json = require("cjson")
local https = require("ssl.https")
local jwt_decoder = require "kong.plugins.jwt.jwt_parser"
local signature = require("kong.plugins.trust-verify-signature.signature")
local btoa = ngx.encode_base64
local kong_meta = require "kong.meta"
local log = require("kong.plugins.plugin-log.log")
local kong = kong

local PLUGIN_NAME = "trust-verify-signature"

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
  elseif conf.manifest_type == "content-digest" and conf.direction == "request" then
    local payload = jwt.claims
    if not payload or not payload["cd"] then
      return false, {status = 401, message = "Signature missing content digest manifest (cd)"}
    end

    if kong.request.get_header("Content-Digest") ~= payload["cd"] then
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
      return log.exit_with_reason(
        {plugin = PLUGIN_NAME, reason = "request is missing signature header '" .. conf.signature_header_key .. "'"},
        401,
        {message = "Missing Signature in " .. conf.signature_header_key}
      )
    end

    local ok,
      err = verify_jwt_signature(conf, sig)

    if not ok then
      return log.exit_with_reason(
        {plugin = PLUGIN_NAME, reason = "request signature verification failed: " .. tostring(err.message)},
        err.status,
        {message = err.message}
      )
    end

    request.set_header("X-Trust-Verify-Signature-Req", "OK")
    log.continue_with_reason({plugin = PLUGIN_NAME, reason = "request signature verified"})
  end
end

function TrustVerifySignatureHandler:header_filter(conf)
  -- if kong.response.status ~= 200 then
  --   return
  -- end

  if conf.direction == "response" then
    kong.log.warn("X-Trust-Verify-Signature-Res")
    local headers = kong.response.get_headers()

    local sig = headers[conf.signature_header_key]
    if not sig then
      return log.exit_with_reason(
        {plugin = PLUGIN_NAME, reason = "upstream response is missing signature header '" .. conf.signature_header_key .. "'"},
        401,
        {message = "Missing Signature in " .. conf.signature_header_key}
      )
    end

    local ok,
      err = verify_jwt_signature(conf, sig)

    if not ok then
      return log.exit_with_reason(
        {plugin = PLUGIN_NAME, reason = "response signature verification failed: " .. tostring(err.message)},
        err.status,
        {message = err.message}
      )
    end

    kong.response.set_header("X-Trust-Verify-Signature-Res", "OK")
    log.continue_with_reason({plugin = PLUGIN_NAME, reason = "response signature verified"})
  end
end

return TrustVerifySignatureHandler
