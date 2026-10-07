local http = require "resty.http"
local cjson = require "cjson.safe"
local base64 = require "ngx.base64"
local encode_base64url = base64.encode_base64url
local openssl_pkey = require "resty.openssl.pkey"
local table_concat = table.concat
local kong = kong
local jwk_sign = require("kong.plugins.trust-sign.sign")
local client_assertion = require("kong.plugins.token-exchange.client_assertion")

--- Exchange client assertion for an access token from Keycloak
-- @param config table Configuration containing:
--   - client_id: The client ID
--   - token_endpoint: The Keycloak token endpoint URL
--   - private_key_location: The private key in PEM format
--   - grant_type: OAuth2 grant type (default: "client_credentials")
--   - scope: Optional scope parameter
--   - timeout: HTTP timeout in milliseconds (default: 10000)
-- @return table|nil Token response containing access_token, token_type, expires_in, etc.
-- @return string|nil Error message if request failed
local function get_access_token(config)
  if not config then
    return nil, "configuration is required"
  end

  -- Create the client assertion JWT
  local client_assertion_token,
    err = client_assertion.create_client_assertion(config)
  if not client_assertion then
    return nil, "failed to create client assertion: " .. (err or "unknown error")
  end

  kong.log.warn("Generated client assertion: ", client_assertion_token)

  -- Prepare token request parameters
  local grant_type = "client_credentials"
  local body_params = {
    grant_type = grant_type,
    client_id = config.client_id,
    client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
    client_assertion = client_assertion_token
  }

  -- Add optional scope if provided
  if config.scope then
    body_params.scope = config.scope
  end

  -- URL-encode the body parameters
  local body_parts = {}
  for key, value in pairs(body_params) do
    table.insert(body_parts, key .. "=" .. ngx.escape_uri(value))
  end
  local request_body = table.concat(body_parts, "&")

  -- Create HTTP client
  local httpc = http.new()
  httpc:set_timeout(config.timeout or 10000)

  -- Make the token request
  local res,
    err =
    httpc:request_uri(
    config.token_endpoint,
    {
      method = "POST",
      body = request_body,
      headers = {
        ["Content-Type"] = "application/x-www-form-urlencoded",
        ["Accept"] = "application/json"
      }
    }
  )

  if not res then
    return nil, "HTTP request failed: " .. (err or "unknown error")
  end

  -- Check HTTP status
  if res.status ~= 200 then
    local error_msg = "token endpoint returned status " .. res.status
    if res.body then
      error_msg = error_msg .. ": " .. res.body
    end
    return nil, error_msg
  end

  -- Parse JSON response
  local token_response,
    decode_err = cjson.decode(res.body)
  if not token_response then
    return nil, "failed to decode token response: " .. (decode_err or "unknown error")
  end

  -- Verify we got an access token
  if not token_response.access_token then
    return nil, "no access_token in response"
  end

  return token_response
end

--- Convenience function to get just the access token string
-- @param config table Configuration (same as get_access_token)
-- @return string|nil The access token, or nil on error
-- @return string|nil Error message if request failed
local function get_access_token_string(config)
  local token_response,
    err = get_access_token(config)
  if not token_response then
    return nil, err
  end

  return token_response.access_token
end

return {
  get_access_token_string = get_access_token_string
}
