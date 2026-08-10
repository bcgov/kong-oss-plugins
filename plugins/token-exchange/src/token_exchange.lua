local client_assertion = require("kong.plugins.token-exchange.client_assertion")
local cjson = require "cjson.safe"
local kong_meta = require "kong.meta"
local kong = kong
local http = require "resty.http"

local function urlencode(str)
  if not str then
    return ""
  end
  str = tostring(str)
  str =
    string.gsub(
    str,
    "([^%w%.%- ])",
    function(c)
      return string.format("%%%02X", string.byte(c))
    end
  )
  str = string.gsub(str, " ", "+")
  return str
end

local function encode_form_data(data)
  local encoded_body = ""
  local first = true
  for key, value in pairs(data) do
    if not first then
      encoded_body = encoded_body .. "&"
    end
    encoded_body = encoded_body .. urlencode(key) .. "=" .. urlencode(value)
    first = false
  end
  return encoded_body
end

local function do_token_exchange(conf)
  -- get the client assertion token
  local client_assertion_token,
    err = client_assertion.create_client_assertion(conf)
  if not client_assertion_token then
    return nil, "failed to create client assertion: " .. (err or "unknown error"), 500
  end

  -- prepare the token exchange request parameters
  local data = {
    client_id = conf.client_id,
    client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
    client_assertion = client_assertion_token,
    grant_type = "urn:ietf:params:oauth:grant-type:token-exchange",
    subject_token = kong.request.get_header("Authorization"):match("Bearer%s+(.+)"),
    subject_token_type = "urn:ietf:params:oauth:token-type:access_token",
    requested_token_type = "urn:ietf:params:oauth:token-type:access_token",
    audience = conf.audience
  }

  -- include any scopes
  if conf.scopes and #conf.scopes > 0 then
    data.scope = table.concat(conf.scopes, " ")
  end

  -- call the token endpoint to exchange the token
  local httpc = http.new()
  httpc:set_timeout(conf.timeout or 10000)

  local res,
    err =
    httpc:request_uri(
    conf.token_endpoint,
    {
      method = "POST",
      headers = {
        ["Content-Type"] = "application/x-www-form-urlencoded",
        ["Accept"] = "application/json"
      },
      body = encode_form_data(data),
      ssl_verify = true
    }
  )
  if not res then
    kong.log.err("HTTP request failed: ", err)
    return nil, {code = "E1"}
  end

  if res.status ~= 200 then
    local decoded_body = cjson.decode(res.body)
    return nil,
      {code = "E2"},
      nil,
      {
        idp_status = res.status,
        idp_response = decoded_body or res.body
      }
  end

  -- decode the token response and return all the data
  local token_response,
    decode_err = cjson.decode(res.body)
  if not token_response then
    kong.log.err("Failed to decode token response: ", decode_err)
    return nil, {code = "E3"}
  end
  if type(token_response.access_token) ~= "string" or token_response.access_token == "" then
    kong.log.err("Token response does not contain a non-empty string access_token")
    return nil, {code = "E3"}
  end

  return token_response
end

return {
  do_token_exchange = do_token_exchange
}
