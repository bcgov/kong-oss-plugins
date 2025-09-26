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
  kong.response.set_header("X-Response-Signer", "v" .. kong_meta.version)
  kong.response.set_header("Content-Type", "application/jws+jwt");
end


function ResponseSignerHandler:body_filter(conf)

  if not is_body_transform_set(conf)
    or not is_json_body(kong.response.get_header("Content-Type"))
  then
    return
  end

  local body = kong.response.get_raw_body()
  if body then
    local json_body, err = transform_json_body(conf, body)
    if err then
      kong.log.warn("body transform failed: " .. err)
      return
    end
    return kong.response.set_raw_body(json_body)
  end
end


return ResponseSignerHandler
