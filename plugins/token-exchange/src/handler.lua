local token_exchange = require("kong.plugins.token-exchange.token_exchange")

local cjson = require "cjson.safe"
local kong_meta = require "kong.meta"
local log = require("kong.plugins.plugin-log.log")
local kong = kong
local http = require "resty.http"

local PLUGIN_NAME = "token-exchange"
local ORIGINAL_AZP_HEADER = "X-SDX-Original-AZP"

local TokenExchangeHandler = {
  PRIORITY = 930,
  VERSION = kong_meta.version
}

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

  -- token exchange
  local token_response,
    err,
    status,
    detail = token_exchange.do_token_exchange(conf)
  if err then
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
  if original_azp then
    request.set_header(ORIGINAL_AZP_HEADER, original_azp)
  end
  log.continue_with_reason({plugin = PLUGIN_NAME, reason = "token exchanged"})
end

return TokenExchangeHandler
