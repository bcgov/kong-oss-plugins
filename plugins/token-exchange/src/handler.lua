local token_exchange = require("kong.plugins.token-exchange.token_exchange")

local cjson = require "cjson.safe"
local kong_meta = require "kong.meta"
local request_id_get = require("kong.observability.tracing.request_id").get
local log = require("kong.plugins.plugin-log.log")
local kong = kong

local PLUGIN_NAME = "token-exchange"
local CONFIGURATION_ERROR_CODE = "SDX_TOKEN_EXCHANGE_CONFIGURATION_ERROR"

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

local function is_invalid_scope(err, detail)
  return type(err) == "table"
    and err.code == "E2"
    and type(detail) == "table"
    and type(detail.idp_response) == "table"
    and detail.idp_response.error == "invalid_scope"
end

local function configuration_error(conf, requested_scopes, detail)
  local request_id = request_id_get() or ""
  local diagnostic = {
    idp_status = detail.idp_status,
    idp_error = "invalid_scope",
    request_id = request_id,
    audience = conf.audience,
    requested_scopes = requested_scopes
  }
  local message = "The SDX token-exchange client is not configured to complete this request. " ..
    "Refer to the SDX Kong token-exchange plugin logs using request ID " .. request_id .. " for details."
  local headers
  if request_id ~= "" then
    headers = { ["X-Kong-Request-Id"] = request_id }
  end

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

  -- token exchange
  local token_response,
    err,
    status,
    detail = token_exchange.do_token_exchange(conf, requested_scopes)
  if err then
    if is_invalid_scope(err, detail) then
      return configuration_error(conf, requested_scopes, detail)
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
