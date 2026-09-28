local token_exchange = require("kong.plugins.token-exchange.token_exchange")

local cjson = require "cjson.safe"
local kong_meta = require "kong.meta"
local request_id_get = require("kong.observability.tracing.request_id").get
local log = require("kong.plugins.plugin-log.log")
local kong = kong

local PLUGIN_NAME = "token-exchange"
local CONFIGURATION_ERROR_CODE = "SDX_TOKEN_EXCHANGE_CONFIGURATION_ERROR"
local AUTHORIZATION_ERROR_CODE = "SDX_TOKEN_EXCHANGE_NOT_AUTHORIZED"

local TokenExchangeHandler = {
  PRIORITY = 930,
  VERSION = kong_meta.version
}

local function subject_scopes(conf)
  local verified_token = kong.ctx.shared.jwt_keycloak_token
  if not verified_token then
    kong.log.warn("No verified subject token is available; using configured token exchange scopes")
    return conf.scopes or {}
  end

  local scope_claim = verified_token and verified_token.claims and verified_token.claims.scope
  if type(scope_claim) ~= "string" then
    return nil, "verified subject token has no string scope claim"
  end

  local scopes = {}
  local seen = {}
  for scope in scope_claim:gmatch("%S+") do
    if not seen[scope] then
      table.insert(scopes, scope)
      seen[scope] = true
    end
  end

  if #scopes == 0 then
    return nil, "verified subject token has an empty scope claim"
  end
  return scopes
end

local function subject_audiences(conf)
  local verified_token = kong.ctx.shared.jwt_keycloak_token
  if not verified_token then
    kong.log.warn("No verified subject token is available; using configured token exchange audience")
    if type(conf.audience) == "string" and conf.audience ~= "" then
      return {conf.audience}
    end
    return {}
  end

  local audience_claim = verified_token.claims and verified_token.claims.aud
  local original_audiences = {}
  if type(audience_claim) == "string" then
    original_audiences[1] = audience_claim
  elseif type(audience_claim) == "table" then
    for _, audience in ipairs(audience_claim) do
      table.insert(original_audiences, audience)
    end
  else
    return nil, "authorization", "verified subject token has no string or array aud claim"
  end

  local normalized = {}
  local seen = {}
  local exchange_client_present = false
  for _, audience in ipairs(original_audiences) do
    if type(audience) ~= "string" or audience == "" then
      return nil, "authorization", "verified subject token has an invalid aud claim", original_audiences
    end
    if audience == conf.client_id then
      exchange_client_present = true
    elseif not seen[audience] then
      table.insert(normalized, audience)
      seen[audience] = true
    end
  end

  if not exchange_client_present then
    return nil, "authorization", "verified subject token audience does not authorize the SDX exchange client", original_audiences
  end
  if type(conf.audience) ~= "string" or conf.audience == "" then
    return nil, "configuration", "consumer token exchange audience is not configured", original_audiences
  end
  if conf.audience == conf.client_id then
    return nil, "configuration", "consumer token exchange audience equals the SDX exchange client", original_audiences
  end

  if not seen[conf.audience] then
    table.insert(normalized, 1, conf.audience)
  else
    for index, audience in ipairs(normalized) do
      if audience == conf.audience and index ~= 1 then
        table.remove(normalized, index)
        table.insert(normalized, 1, audience)
        break
      end
    end
  end
  return normalized, nil, nil, original_audiences
end

local function is_exchange_configuration_error(err, detail)
  return type(err) == "table"
    and err.code == "E2"
    and type(detail) == "table"
    and type(detail.idp_response) == "table"
    and (detail.idp_response.error == "invalid_scope" or detail.idp_response.error == "invalid_target")
end

local function request_context()
  local request_id = request_id_get() or ""
  local headers
  if request_id ~= "" then
    headers = { ["X-Kong-Request-Id"] = request_id }
  end
  return request_id, headers
end

local function configuration_error(conf, requested_scopes, requested_audiences, detail, reason)
  local request_id, headers = request_context()
  local idp_response = detail and detail.idp_response
  local diagnostic = {
    idp_status = detail and detail.idp_status,
    idp_error = type(idp_response) == "table" and idp_response.error or nil,
    request_id = request_id,
    configured_audience = conf.audience,
    requested_audiences = requested_audiences,
    requested_scopes = requested_scopes,
    configuration_reason = reason
  }
  local message = "The SDX token-exchange client is not configured to complete this request. " ..
    "Refer to the SDX Kong token-exchange plugin logs using request ID " .. request_id .. " for details."

  kong.log.err("Token exchange configuration error: ", cjson.encode(diagnostic))
  return log.exit_with_reason(
    {
      plugin = PLUGIN_NAME,
      reason = "token exchange client configuration error",
      detail = diagnostic
    },
    500,
    {
      message = message,
      error = { code = CONFIGURATION_ERROR_CODE }
    },
    headers
  )
end

local function authorization_error(conf, reason, original_audiences)
  local request_id, headers = request_context()
  local diagnostic = {
    request_id = request_id,
    authorization_reason = reason,
    exchange_client_id = conf.client_id,
    original_audiences = original_audiences
  }
  local message = "The supplied token is not authorized for SDX token exchange. " ..
    "Refer to the SDX documentation and use request ID " .. request_id .. " when requesting support."

  kong.log.err("Token exchange authorization error: ", cjson.encode(diagnostic))
  return log.exit_with_reason(
    {
      plugin = PLUGIN_NAME,
      reason = "subject token not authorized for token exchange",
      detail = diagnostic
    },
    400,
    {
      message = message,
      error = { code = AUTHORIZATION_ERROR_CODE }
    },
    headers
  )
end

function TokenExchangeHandler:access(conf)
  local request = kong.service.request

  kong.log.warn("Token Exchange")

  local requested_scopes, scope_err = subject_scopes(conf)
  if not requested_scopes then
    kong.log.err("Unable to derive token exchange scopes: ", scope_err)
    return log.exit_with_reason(
      {plugin = PLUGIN_NAME, reason = scope_err},
      400,
      {
        message = "Token exchange failed",
        error = {code = "E4"}
      }
    )
  end

  local requested_audiences, audience_error_type, audience_err, original_audiences = subject_audiences(conf)
  if not requested_audiences then
    if audience_error_type == "configuration" then
      return configuration_error(conf, requested_scopes, nil, nil, audience_err)
    end
    return authorization_error(conf, audience_err, original_audiences)
  end

  -- token exchange
  local token_response,
    err,
    status,
    detail = token_exchange.do_token_exchange(conf, requested_scopes, requested_audiences)
  if err then
    if is_exchange_configuration_error(err, detail) then
      return configuration_error(conf, requested_scopes, requested_audiences, detail)
    end

    kong.log.err("Error during token exchange: ", err)
    local error_code = type(err) == "table" and err.code or err
    local plugin_result = {
      plugin = PLUGIN_NAME,
      reason = "token exchange with IdP failed: " .. tostring(error_code)
    }
    if detail then
      plugin_result.detail = detail
    end

    return log.exit_with_reason(
      plugin_result,
      status or 400,
      {
        message = "Token exchange failed",
        error = err
      }
    )
  end

  request.set_header("Authorization", "Bearer " .. token_response.access_token)
  log.continue_with_reason({plugin = PLUGIN_NAME, reason = "token exchanged"})
end

return TokenExchangeHandler
