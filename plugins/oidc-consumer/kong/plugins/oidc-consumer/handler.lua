local kong_utils = require "kong.tools.utils"
local constants = require "kong.constants"

local utils = require("kong.plugins.oidc-consumer.utils")

local ngx_set_header = ngx.req.set_header
local create_consumer = false

local OidcConsumerHandler = {
  PRIORITY = 960,
  VERSION = "1.0.0",
}

local function load_consumer_by_username(username)
  local result, err = kong.db.consumers:select_by_username(username)
  if not result then
      return nil, err
  end
  kong.log.info("Found consumer")
  return result
end

local function set_consumer(consumer, credential, token)
  local set_header = kong.service.request.set_header
  local clear_header = kong.service.request.clear_header

  if consumer and consumer.id then
      set_header(constants.HEADERS.CONSUMER_ID, consumer.id)
  else
      clear_header(constants.HEADERS.CONSUMER_ID)
  end

  if consumer and consumer.custom_id then
      set_header(constants.HEADERS.CONSUMER_CUSTOM_ID, consumer.custom_id)
  else
      clear_header(constants.HEADERS.CONSUMER_CUSTOM_ID)
  end

  if consumer and consumer.username then
      set_header(constants.HEADERS.CONSUMER_USERNAME, consumer.username)
  else
      clear_header(constants.HEADERS.CONSUMER_USERNAME)
  end

  kong.client.authenticate(consumer, credential)

end

local function match_consumer(consumer_id)
  local consumer, err

  local consumer_cache_key = "username_key_" .. consumer_id
  kong.log.info('Cache key ' .. consumer_cache_key)
  consumer, err = kong.cache:get(consumer_cache_key, nil, load_consumer_by_username, consumer_id)

  if err then
      kong.log.err(err)
  end

  if not consumer then
    if create_consumer then 
      consumer = kong.db.consumers:insert {
        id = kong_utils.uuid(),
        username = consumer_id
      }
  
      if consumer then
        ngx.log(ngx.DEBUG, "New consumer created from oidc userInfo")
        return consumer
      end
    end

    return false, { status = 401, message = "Unable to find consumer" }
  end

  if consumer then
    ngx.log(ngx.DEBUG, "OidcConsumerHandler Setting consumer found")
    set_consumer(consumer, nil, nil)
  end

  return true
end


local function handleOidcHeader(oidcUserInfo, config, ngx)
  local userInfo = utils.decodeUserInfo(oidcUserInfo, ngx)
  local usernameField = config.username_field
  create_consumer = config.create_consumer

  if not usernameField then 
    usernameField = 'email'
  end

  local usernameForLookup = userInfo[usernameField]
  if usernameForLookup then 
    -- get consumer by the username if possible
    local ok, err = match_consumer(usernameForLookup)

    if not ok then
      return kong.response.exit(err.status, err.errors or { message = err.message })
    end
  else
    ngx.log(ngx.DEBUG, "OidcConsumerHandler No username field found on decoded oidc userInfo header")
  end

end

function OidcConsumerHandler:access(config)
  local oidcUserInfoHeader = ngx.req.get_headers()["X-Userinfo"]

  if oidcUserInfoHeader then
    ngx.log(ngx.DEBUG, "OidcConsumerHandler X-Userinfo  header found:  " .. oidcUserInfoHeader)
    handleOidcHeader(oidcUserInfoHeader, config, ngx)
  else
    ngx.log(ngx.DEBUG, "OidcConsumerHandler ignoring request, path: " .. ngx.var.request_uri)
  end

  ngx.log(ngx.DEBUG, "OidcConsumerHandler done")
end


return OidcConsumerHandler
