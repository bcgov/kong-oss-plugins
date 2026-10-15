local body_transformer = require "kong.plugins.response-signer.body_transformer"
local header_transformer = require "kong.plugins.response-signer.header_transformer"
local kong_meta = require "kong.meta"


local transform_headers = header_transformer.transform_headers
local transform_json_body = body_transformer.transform_json_body


local is_body_transform_set = header_transformer.is_body_transform_set
local is_json_body = header_transformer.is_json_body
local kong = kong


local ResponseSignerHandler = {
  PRIORITY = 800,
  VERSION = kong_meta.version,
}


function ResponseSignerHandler:header_filter(conf)
  -- transform_headers(conf, kong.response.get_headers())
  local clear_header = kong.response.clear_header

  clear_header("Content-Length")
  kong.response.set_header("X-Response-Signer", "v" .. kong_meta.version)
  kong.response.set_header("Content-Type", "application/jws+jwt");
end


function ResponseSignerHandler:body_filter(conf)

  local body = kong.response.get_raw_body()
  if body then
    local jwt_body, err = transform_json_body(conf, body)
    if err then
      kong.log.warn("body transform failed: " .. err)
      return
    end
    return kong.response.set_raw_body(jwt_body)
  end
end


return ResponseSignerHandler
