local filter = require("kong.plugins.trust-sign.signature_base")
local kong_meta = require "kong.meta"
local btoa = ngx.encode_base64
local kong = kong

local TrustSignHandler = {
  PRIORITY = 630,
  VERSION = kong_meta.version
}

function TrustSignHandler:access(conf)
  kong.log.warn("Trust Sign")
end

function TrustSignHandler:header_filter(conf)
  kong.log.warn("Trust Sign - Header Filter")

  local headers = kong.request.get_headers()

  local tag = "trust-sign"
  local keyid = conf.keyid
  local kong_request = kong.request
  local signature_label = conf.signature_label
  local signature_input = conf.signature_label .. "=" .. conf.signature_input .. ";created=" .. (ngx.now() * 1000) .. ";keyid=\"" .. keyid .. "\";tag=\"" .. tag .. "\""

  kong.response.set_header("Signature-Input", signature_input)

  local input_message, err = filter.get_signature_base(headers, kong_request, signature_label, signature_input)
  if not input_message then
    kong.response.set_header("X-Trust-Sign-Error", "Signature Base Error - " .. err)
    return
  end

  local algorithm = conf.algorithm
  local signature = filter.sign(conf, input_message, algorithm)
  if signature then
    kong.response.set_header("Signature", signature_label .. "=:" .. btoa(signature) .. ":")
  end
end

function TrustSignHandler:body_filter(conf)
  kong.log.warn("Trust Sign - Body Filter")
end

return TrustSignHandler
