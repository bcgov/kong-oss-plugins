local http = require("resty.http")
local cjson = require("cjson.safe")
local log = require("kong.plugins.plugin-log.log")

local PLUGIN_NAME = "pep"

local plugin = {
  PRIORITY = 1000,
  VERSION = "0.1"
}

function prepare_pep_request()
  local request_data = {
    method = ngx.req.get_method(),
    path = ngx.var.request_uri,
    host = ngx.var.host
    -- headers = ngx.req.get_headers(),
    -- query = ngx.req.get_uri_args()
  }

  local params = kong.request.get_uri_captures()

  if params and params.named then
    request_data.named_params = params.named
  end

  -- read body if it's a POST/PUT/PATCH
  -- if request_data.method == "POST" or request_data.method == "PUT" or request_data.method == "PATCH" then
  --   ngx.req.read_body()
  --   local body_data = ngx.req.get_body_data()
  --   if body_data then
  --     request_data.body = body_data
  --   end
  -- end

  -- if there is an authorization token, pass some details
  if kong.ctx.shared and kong.ctx.shared.jwt_keycloak_token then
    request_data.token = kong.ctx.shared.jwt_keycloak_token.claims
  end

  return cjson.encode({input = request_data})
end

function plugin:access(conf)
  local httpc = http.new()

  -- set auth header if it's specified
  local headers = {}
  if conf.auth_header_name and conf.auth_header_value then
    kong.log.debug("setting auth header with name ", conf.auth_header_name)
    headers[conf.auth_header_name] = conf.auth_header_value
  end

  local body = prepare_pep_request()

  -- single-shot requests use the `request_uri` interface.
  local res,
    err =
    httpc:request_uri(
    conf.target_url,
    {
      method = "POST",
      headers = headers,
      body = body
    }
  )

  if not res then
    ngx.log(ngx.ERR, "request failed: ", err)
    return log.exit_with_reason(
      {plugin = PLUGIN_NAME, reason = "policy engine unreachable: " .. tostring(err)},
      400,
      {message = "failed to call policy engine"}
    )
  end

  if res.status ~= 200 then
    ngx.log(ngx.ERR, "policy engine returned non-200 status: ", res.status)
    return log.exit_with_reason(
      {plugin = PLUGIN_NAME, reason = "policy engine returned non-200 status: " .. tostring(res.status)},
      400,
      {message = "policy engine error"}
    )
  end

  kong.log.warn("sent: ", body)
  kong.log.warn("response status: ", res.status)
  kong.log.warn("response body: ", res.body)

  -- decode
  local body_t,
    err = cjson.decode(res.body)
  if err then
    kong.log.err("response body: ", res.body)
    return log.exit_with_reason(
      {plugin = PLUGIN_NAME, reason = "failed to decode policy engine response body as JSON"},
      400,
      {message = "unable to decode the callout response in pep plugin"}
    )
  end

  kong.log.inspect("pep response: ", body_t) -- DEBUGGING

  -- find the detail we want
  -- for decisions, we are looking for a boolean that indicates allow/deny
  -- for data retrieval, we are looking for a table of data to pass back to the
  -- consumer
  for _, v in ipairs(conf.json_locator) do
    kong.log.warn("body is type ", type(body_t), " looking for key ", v)

    kong.log.warn("bool? ", body_t[v])

    if type(body_t) == "table" and body_t[v] then
      body_t = body_t[v]
    elseif type(body_t[v]) == "boolean" then
      body_t = body_t[v]
    else
      return log.exit_with_reason(
        {plugin = PLUGIN_NAME, reason = "json locator element '" .. v .. "' not found in policy engine response"},
        400,
        {message = "json element " .. v .. " is not next in the tree"}
      )
    end
  end

  if conf.result_type == "decision" then
    if type(body_t) ~= "boolean" then
      return log.exit_with_reason(
        {plugin = PLUGIN_NAME, reason = "located json element is not a boolean as required by 'decision' result_type"},
        400,
        {message = "the located json element is not a boolean for a 'decision' result_type"}
      )
    end

    if body_t == true then
      kong.service.request.set_header("x-policy-result", "allow")
      log.continue_with_reason({plugin = PLUGIN_NAME, reason = "policy allow"})
    else
      return log.exit_with_reason(
        {plugin = PLUGIN_NAME, reason = "policy engine denied the request"},
        403,
        {message = "access denied by policy engine"}
      )
    end
  else
    if type(body_t) ~= "table" then
      return log.exit_with_reason(
        {plugin = PLUGIN_NAME, reason = "located json element is not a table as required by 'table' result_type"},
        400,
        {message = "the located json element is not a table for a 'table' result_type"}
      )
    end

    return log.exit_with_reason(
      {plugin = PLUGIN_NAME, reason = "returning policy engine data payload to the consumer"},
      200,
      body_t
    )
  end
end

return plugin
