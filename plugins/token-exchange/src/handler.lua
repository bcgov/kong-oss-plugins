local kong_meta = require "kong.meta"
local kong = kong

local TokenExchangeHandler = {
  PRIORITY = 930,
  VERSION = kong_meta.version,
}


function TokenExchangeHandler:access(conf)
  kong.log.warn("Token Exchange")
end

function TokenExchangeHandler:header_filter(conf)
  kong.log.warn("Token Exchange - Header Filter")
end

function TokenExchangeHandler:body_filter(conf)
  kong.log.warn("Token Exchange - Body Filter")
  -- local body = kong.response.get_raw_body()
  -- return kong.response.set_raw_body(body)
end

return TokenExchangeHandler
