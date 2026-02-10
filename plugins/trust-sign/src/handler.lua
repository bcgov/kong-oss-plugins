local jwt_decoder = require "kong.plugins.jwt.jwt_parser"
local digest_mod = require("kong.plugins.trust-sign.digest")
local filter = require("kong.plugins.trust-sign.signature_base")
local jwk_sign = require("kong.plugins.trust-sign.sign")
local request_id_get = require("kong.observability.tracing.request_id").get
local kong_meta = require "kong.meta"
local btoa = ngx.encode_base64
local kong = kong

local TrustSignHandler = {
  PRIORITY = 630,
  VERSION = kong_meta.version
}

local function get_ids_from_service()
  local svc = kong.router.get_service()
  -- split svc tags by ":" and find the tags for client and service
  local svc_tags = svc and svc.tags or {}
  local client_tag = ""
  local service_tag = ""
  for _, tag in ipairs(svc_tags) do
    local key,
      value = tag:match("^(.-):(.-)$")
    if key == "client" then
      client_tag = value
    elseif key == "service" then
      service_tag = value
    end
  end
  return client_tag, service_tag
end

function TrustSignHandler:access(conf)
  local request = kong.service.request

  -- Enable request buffering to read the full body
  -- in the header_filter phase
  request.enable_buffering()

  if conf.direction ~= "request" then
    return
  end

  kong.log.warn("Trust Sign - Access for Request")

  local body_digest = kong.request.get_header("Content-Digest")

  if body_digest == nil then
    local alg = "sha-256"
    kong.log.warn("Content-Digest header not present, generating digest")
    local body = kong.request.get_raw_body()
    if body == nil then
      kong.log.warn("Body is nil - no raw body available")
    elseif body == "" then
      local dig = digest_mod.digest(body, alg)
      body_digest = alg .. "=:" .. btoa(dig) .. ":"
      request.set_header("Content-Digest", body_digest)
    else
      local dig = digest_mod.digest(body, alg)
      body_digest = alg .. "=:" .. btoa(dig) .. ":"
      request.set_header("Content-Digest", body_digest)
    end
  end

  local headers = kong.request.get_headers()

  -- local tag = "trust-sign"
  -- local keyid = conf.keyid
  -- local kong_request = kong.request
  -- local signature_label = conf.signature_label
  -- local signature_input =
  --   conf.signature_label ..
  --   "=" .. conf.signature_input .. ";created=" .. (ngx.now() * 1000) .. ';keyid="' .. keyid .. '";tag="' .. tag .. '"'

  -- request.set_header("Signature-Input", signature_input)

  -- local input_message,
  --   err = filter.get_signature_base(headers, kong_request, signature_label, signature_input)
  -- if not input_message then
  --   request.set_header("X-Trust-Sign-Error", "Signature Base Error - " .. err)
  --   return
  -- end

  -- local hash_alg = conf.hash_alg
  -- local signature = filter.sign(conf, input_message, hash_alg)
  -- if signature then
  --   request.set_header("Signature", signature_label .. "=:" .. btoa(signature) .. ":")
  -- end

  local client_tag,
    service_tag = get_ids_from_service()

  local request_id = request_id_get() or ""

  local manifest = {
    request_id = request_id,
    client_id = client_tag,
    service_id = service_tag,
    digest = body_digest,
    jwks_uri = conf.jwks_uri
  }

  local jwt = jwk_sign.sign_jwt(conf, manifest)
  request.set_header(conf.signature_header_key, jwt)
end

function TrustSignHandler:header_filter(conf)
  if conf.direction ~= "response" then
    return
  end

  if kong.response.get_source() ~= "service" then
    return
  end

  kong.log.warn("Trust Sign - Header Filter for Response")

  local body_digest = kong.response.get_header("Content-Digest")

  if body_digest == nil then
    kong.log.warn("Content-Digest header not present, generating digest")
    local body = kong.service.response.get_raw_body()
    if body == nil then
      kong.log.warn("Body is nil - no raw body available")
    elseif body == "" then
      kong.log.warn("Body is empty string")
    else
      local alg = "sha-256"
      local dig = digest_mod.digest(body, alg)
      body_digest = alg .. "=:" .. btoa(dig) .. ":"
      kong.response.set_header("Content-Digest", body_digest)
    end
  end

  kong.log.warn("Trust Sign - Header Filter")

  local headers = kong.response.get_headers()

  -- local tag = "trust-sign"
  -- local keyid = conf.keyid
  -- local kong_request = kong.request
  -- local signature_label = conf.signature_label
  -- local signature_input =
  --   conf.signature_label ..
  --   "=" .. conf.signature_input .. ";created=" .. (ngx.now() * 1000) .. ';keyid="' .. keyid .. '";tag="' .. tag .. '"'

  -- kong.response.set_header("Signature-Input", signature_input)

  -- local input_message,
  --   err = filter.get_signature_base(headers, kong_request, signature_label, signature_input)
  -- if not input_message then
  --   kong.response.set_header("X-Trust-Sign-Error", "Signature Base Error - " .. err)
  --   return
  -- end

  -- kong.log.warn("Signature Base Message: \n" .. input_message)

  -- kong.response.set_header("Signature-Debug", btoa(input_message))

  -- local algorithm = conf.hash_alg
  -- local signature = filter.sign(conf, input_message, algorithm)
  -- if signature then
  --   kong.response.set_header("Signature", signature_label .. "=:" .. btoa(signature) .. ":")
  -- end

  local req_token = kong.request.get_header("X-Edge-Token")
  if not req_token then
    -- return kong.response.exit(403, {message = "Missing X-Edge-Token header"})

    local manifest = {
      jwks_uri = conf.jwks_uri
    }

    local jwt = jwk_sign.sign_jwt(conf, manifest)
    kong.response.set_header(conf.signature_header_key, jwt)
    return
  end

  local req_token_jwt,
    err = jwt_decoder:new(req_token)
  if err then
    return kong.response.exit(
      403,
      {
        message = "Bad token",
        error = err
      }
    )
  end

  local req_claims = req_token_jwt.claims

  local manifest = {
    request_id = req_claims.request_id,
    client_id = req_claims.client_id,
    service_id = req_claims.service_id,
    digest = req_claims.digest,
    jwks_uri = conf.jwks_uri
  }

  local jwt = jwk_sign.sign_jwt(conf, manifest)
  kong.response.set_header(conf.signature_header_key, jwt)
end

return TrustSignHandler
