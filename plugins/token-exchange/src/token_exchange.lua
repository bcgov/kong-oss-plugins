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

local function unique_scopes(scope_string)
  if type(scope_string) ~= "string" then
    return nil
  end

  local scopes = {}
  local seen = {}
  for scope in scope_string:gmatch("%S+") do
    if not seen[scope] then
      table.insert(scopes, scope)
      seen[scope] = true
    end
  end
  return scopes
end

local function same_scope_set(requested_scopes, granted_scopes)
  if #requested_scopes ~= #granted_scopes then
    return false
  end

  local requested = {}
  for _, scope in ipairs(requested_scopes) do
    requested[scope] = true
  end
  for _, scope in ipairs(granted_scopes) do
    if not requested[scope] then
      return false
    end
  end
  return true
end

local function do_token_exchange(conf, requested_scopes)
  local authorization = kong.request.get_header("Authorization")
  local subject_token = type(authorization) == "string"
    and authorization:match("Bearer%s+(.+)")
  if not subject_token then
    return nil, {code = "E4"}, 401
  end

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
    subject_token = subject_token,
    subject_token_type = "urn:ietf:params:oauth:token-type:access_token",
    requested_token_type = "urn:ietf:params:oauth:token-type:access_token",
    audience = conf.audience
  }

  -- Limit the exchanged token to the scopes in the verified subject token.
  if requested_scopes and #requested_scopes > 0 then
    data.scope = table.concat(requested_scopes, " ")
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

  -- RFC 8693 allows scope to be omitted when the granted scopes are identical
  -- to those requested. When it is present, record a difference for operators
  -- but honor the authorization server's successful response.
  if token_response.scope ~= nil then
    local granted_scopes = unique_scopes(token_response.scope)
    if not granted_scopes or not same_scope_set(requested_scopes or {}, granted_scopes) then
      kong.log.warn(
        "Token exchange granted scopes differ from requested scopes: ",
        cjson.encode({
          requested_scopes = requested_scopes,
          granted_scopes = granted_scopes,
          granted_scope_value_type = type(token_response.scope)
        })
      )
    end
  end

  return token_response
end

return {
  do_token_exchange = do_token_exchange,
  unique_scopes = unique_scopes
}
