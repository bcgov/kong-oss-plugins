local token_exchange = require("kong.plugins.token-exchange.token_exchange")

local cjson = require "cjson.safe"
local kong_meta = require "kong.meta"
local kong = kong
local http = require "resty.http"

local TokenExchangeHandler = {
  PRIORITY = 930,
  VERSION = kong_meta.version
}

function TokenExchangeHandler:access(conf)
  local request = kong.service.request

  kong.log.warn("Token Exchange")

  -- token exchange
  local token_response,
    err = token_exchange.do_token_exchange(conf)
  if err then
    kong.log.err("Error during token exchange: ", err)
    return kong.response.exit(
      400,
      {
        message = "Token exchange failed",
        error = err
      }
    )
  end

  request.set_header("Authorization", "Bearer " .. token_response.access_token)
end

return TokenExchangeHandler
