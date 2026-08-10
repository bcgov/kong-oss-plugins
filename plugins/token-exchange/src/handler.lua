local token_exchange = require("kong.plugins.token-exchange.token_exchange")

local cjson = require "cjson.safe"
local kong_meta = require "kong.meta"
local log = require("kong.plugins.plugin-log.log")
local kong = kong
local http = require "resty.http"

local PLUGIN_NAME = "token-exchange"

local TokenExchangeHandler = {
  PRIORITY = 930,
  VERSION = kong_meta.version
}

function TokenExchangeHandler:access(conf)
  local request = kong.service.request

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
  log.continue_with_reason({plugin = PLUGIN_NAME, reason = "token exchanged"})
end

return TokenExchangeHandler
