local digest_mod = require("kong.plugins.trust-sign.digest")
local filter = require("kong.plugins.trust-sign.signature_base")
local kong_meta = require "kong.meta"
local btoa = ngx.encode_base64
local kong = kong

local TrustSignHandler = {
  PRIORITY = 630,
  VERSION = kong_meta.version
}

function TrustSignHandler:access(conf)
  local request = kong.service.request

  -- Enable request buffering to read the full body
  -- in the header_filter phase
  request.enable_buffering()

  if conf.direction ~= "request" then
    return
  end

  kong.log.warn("Trust Sign - Access for Request")

  local headers = kong.request.get_headers()

  local tag = "trust-sign"
  local keyid = conf.keyid
  local kong_request = kong.request
  local signature_label = conf.signature_label
  local signature_input = conf.signature_label .. "=" .. conf.signature_input .. ";created=" .. (ngx.now() * 1000) .. ";keyid=\"" .. keyid .. "\";tag=\"" .. tag .. "\""

  request.set_header("Signature-Input", signature_input)

  local input_message, err = filter.get_signature_base(headers, kong_request, signature_label, signature_input)
  if not input_message then
    request.set_header("X-Trust-Sign-Error", "Signature Base Error - " .. err)
    return
  end

  local algorithm = conf.algorithm
  local signature = filter.sign(conf, input_message, algorithm)
  if signature then
    request.set_header("Signature", signature_label .. "=:" .. btoa(signature) .. ":")
  end
end

function TrustSignHandler:header_filter(conf)
  if conf.direction ~= "response" then
    return
  end

  if kong.response.get_source() ~= "service" then
    return
  end

  if kong.response.get_header("Content-Digest") == nil then
    kong.log.warn("Content-Digest header not present, generating digest")
    local body = kong.service.response.get_raw_body()
    if body == nil then
      kong.log.warn("Body is nil - no raw body available")
    elseif body == "" then
      kong.log.warn("Body is empty string")
    else
      local alg = "sha-256"
      local dig = digest_mod.digest(body, alg)
      kong.response.set_header("Content-Digest", alg .. "=:" .. btoa(dig) .. ":")
    end 
  end
  
  kong.log.warn("Trust Sign - Header Filter")

  local headers = kong.response.get_headers()

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

  kong.response.set_header("Signature-Debug", btoa(input_message))

  local algorithm = conf.algorithm
  local signature = filter.sign(conf, input_message, algorithm)
  if signature then
    kong.response.set_header("Signature", signature_label .. "=:" .. btoa(signature) .. ":")
  end
end

return TrustSignHandler
