local token_exchange = require("kong.plugins.token-exchange.token_exchange")

local cjson = require "cjson.safe"
local kong_meta = require "kong.meta"
local request_id_get = require("kong.observability.tracing.request_id").get
local log = require("kong.plugins.plugin-log.log")
local kong = kong
local http = require "resty.http"

local PLUGIN_NAME = "token-exchange"
local CONFIGURATION_ERROR_CODE = "SDX_TOKEN_EXCHANGE_CONFIGURATION_ERROR"
local ORIGINAL_AZP_HEADER = "X-SDX-Original-AZP"
local AUTHORIZATION_ERROR_CODE = "SDX_TOKEN_EXCHANGE_NOT_AUTHORIZED"

local TokenExchangeHandler = {
  PRIORITY = 930,
  VERSION = kong_meta.version
}

local function subject_scopes(conf)
  if conf.scope_source ~= "verified_subject_token" then
    return conf.scopes or {}
  end

  if type(conf.scopes) ~= "table" or #conf.scopes == 0 then
    return nil,
      "SDX-managed application scope allowlist is missing or empty",
      "configuration"
  end

  local allowed = {}
  for _, scope in ipairs(conf.scopes) do
    if type(scope) ~= "string" or scope == "" or scope:find("%s") then
      return nil,
        "SDX-managed application scope allowlist contains an invalid OAuth scope",
        "configuration"
    end
    allowed[scope] = true
  end

  local verified_token = kong.ctx.shared.jwt_keycloak_token
  if not verified_token then
    return nil, "verified subject token is unavailable"
  end

  local scope_claim = verified_token and verified_token.claims and verified_token.claims.scope
  if type(scope_claim) ~= "string" then
    return nil, "verified subject token has no string scope claim"
  end

  local subject_scope_values = token_exchange.unique_scopes(scope_claim)
  if #subject_scope_values == 0 then
    return nil, "verified subject token has an empty scope claim"
  end

  local target_scope = conf.target_privacy_zone_scope
  if target_scope ~= nil and
    (type(target_scope) ~= "string" or target_scope == "" or target_scope:find("%s")) then
    return nil,
      "target privacy-zone scope must contain exactly one non-empty OAuth scope value",
      "configuration"
  end

  local scopes = {}
  local excluded = {}
  local selected = {}
  for _, scope in ipairs(subject_scope_values) do
    if allowed[scope] or scope == target_scope then
      table.insert(scopes, scope)
      selected[scope] = true
    else
      table.insert(excluded, scope)
    end
  end

  if target_scope ~= nil and not selected[target_scope] then
    table.insert(scopes, target_scope)
  end

  return scopes, nil, nil, excluded
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
  local authorized_party = verified_token.claims and verified_token.claims.azp
  if type(authorized_party) ~= "string" or authorized_party == "" then
    authorized_party = nil
  end
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
    end
    -- The subject token authorized party identifies the client that obtained
    -- the token, not a downstream resource. Exclude that value only when it
    -- came from the original audience claim. Required and configured
    -- audiences are added independently below.
    if audience ~= authorized_party and not seen[audience] then
      table.insert(normalized, audience)
      seen[audience] = true
    end
  end

  if not exchange_client_present then
    return nil, "authorization", "verified subject token audience does not authorize the SDX exchange client", original_audiences
  end
  if not seen[conf.client_id] then
    table.insert(normalized, conf.client_id)
    seen[conf.client_id] = true
  end
  if type(conf.audience) == "string" and conf.audience ~= "" then
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
  end
  return normalized, nil, nil, original_audiences
end

local function is_exchange_configuration_error(err, detail)
  if type(err) ~= "table"
    or err.code ~= "E2"
    or type(detail) ~= "table"
    or type(detail.idp_response) ~= "table" then
    return false
  end

  local idp_error = detail.idp_response.error
  local error_description = detail.idp_response.error_description
  return idp_error == "invalid_scope"
    or idp_error == "invalid_target"
    or idp_error == "invalid_client"
    or (idp_error == "invalid_request"
      and type(error_description) == "string"
      and error_description:sub(1, 33) == "Requested audience not available:")
end

local function configuration_error(conf, requested_scopes, requested_audiences, detail, reason)
  local request_id = request_id_get() or ""
  local idp_response = detail and detail.idp_response
  local diagnostic = {
    idp_status = detail and detail.idp_status,
    idp_error = type(idp_response) == "table" and idp_response.error or nil,
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
    }
  )
end

local function authorization_error(conf, reason, original_audiences)
  local request_id = request_id_get() or ""
  local diagnostic = {
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
    }
  )
end

function TokenExchangeHandler:access(conf)
  local request = kong.service.request
  local verified_token = kong.ctx.shared.jwt_keycloak_token
  local original_azp = verified_token and verified_token.claims and verified_token.claims.azp

  -- Never forward a caller-supplied identity header. The header is populated
  -- below only from the JWT that jwt-keycloak has already verified.
  request.clear_header(ORIGINAL_AZP_HEADER)

  if type(original_azp) ~= "string" or original_azp == "" then
    original_azp = nil
    kong.log.warn("Verified subject token has no usable azp claim; ", ORIGINAL_AZP_HEADER, " will be omitted")
  end

  kong.log.warn("Token Exchange")

  local requested_scopes, scope_err, scope_error_type, excluded_scopes =
    subject_scopes(conf)
  if not requested_scopes then
    kong.log.err("Unable to derive token exchange scopes: ", scope_err)
    if scope_error_type == "configuration" then
      return configuration_error(conf, {}, {}, nil, scope_err)
    end
    return log.exit_with_reason(
      {plugin = PLUGIN_NAME, reason = scope_err},
      500,
      {
        message = "Token exchange failed",
        error = {code = "E4"}
      }
    )
  end

  if conf.scope_source == "verified_subject_token" then
    kong.log.info("Token exchange scope filter: ", cjson.encode({
      selected_scopes = requested_scopes,
      excluded_scopes = excluded_scopes or {}
    }))
  end

  local requested_audiences, _, audience_err, original_audiences = subject_audiences(conf)
  if not requested_audiences then
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
      status or 500,
      {
        message = "Token exchange failed",
        error = err
      }
    )
  end

  request.set_header("Authorization", "Bearer " .. token_response.access_token)
  if original_azp then
    request.set_header(ORIGINAL_AZP_HEADER, original_azp)
  end
  log.continue_with_reason({plugin = PLUGIN_NAME, reason = "token exchanged"})
end

return TokenExchangeHandler
