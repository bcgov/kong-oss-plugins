local ConsumerMatch = {}

local UNMATCHED_CONSUMER_MESSAGE = "Unable to match token to a Kong consumer"
local LOOKUP_FAILURE_MESSAGE = "An unexpected error occurred during authentication"
local CLIENT_IDENTIFIER_CLAIMS = {"azp", "client_id"}

local function log_attributes(claim_name, claims)
  local attributes = {
    consumer_match_claim = claim_name
  }

  -- These client identifiers are safe and useful for service-provider
  -- troubleshooting. Do not expose values from arbitrary configured claims.
  for _, name in ipairs(CLIENT_IDENTIFIER_CLAIMS) do
    local value = claims and claims[name]
    if type(value) == "string" and not value:match("^%s*$") then
      attributes[name] = value
    end
  end

  return attributes
end

local function rejected(reason, claim_name, claims)
  kong.log.debug("Consumer match failed: " .. reason)

  return false, {
    status = 401,
    message = UNMATCHED_CONSUMER_MESSAGE,
    log_reason = reason,
    log_attributes = log_attributes(claim_name, claims)
  }
end

local function unmatched(conf, reason, claim_name, claims)
  if conf.consumer_match_ignore_not_found then
    kong.log.debug("Consumer match ignored: " .. reason)
    return true
  end

  return rejected(reason, claim_name, claims)
end

local function match_claim_value(conf, claims)
  local claim_name = conf.consumer_match_claim
  if type(claim_name) ~= "string" or claim_name:match("^%s*$") then
    return nil, "configured claim name is invalid"
  end

  local claim_value = claims[claim_name]
  if type(claim_value) ~= "string" or claim_value:match("^%s*$") then
    return nil, "configured claim is missing or is not a non-empty string"
  end

  return claim_value
end

local function custom_id_cache_key(custom_id)
  return "custom_id_key_" .. custom_id
end

local function load_consumer_by_custom_id(custom_id)
  return kong.db.consumers:select_by_custom_id(custom_id)
end

function ConsumerMatch.match(conf, jwt, set_consumer)
  local consumer_id, invalid_reason = match_claim_value(conf, jwt.claims)
  if not consumer_id then
    return rejected(invalid_reason, conf.consumer_match_claim, jwt.claims)
  end

  local consumer, err
  if conf.consumer_match_claim_custom_id then
    consumer, err = kong.cache:get(
      custom_id_cache_key(consumer_id),
      nil,
      load_consumer_by_custom_id,
      consumer_id
    )
  else
    consumer, err = kong.cache:get(
      kong.db.consumers:cache_key(consumer_id),
      nil,
      kong.client.load_consumer,
      consumer_id,
      -- Forwarded to load_consumer as search_by_username=true. This is
      -- required when the configured claim contains a non-UUID username.
      true
    )
  end

  if err then
    kong.log.err("Consumer lookup failed for the configured match claim: " .. tostring(err))
    return false, {
      status = 500,
      message = LOOKUP_FAILURE_MESSAGE,
      log_reason = "consumer lookup failed: " .. tostring(err),
      log_attributes = log_attributes(conf.consumer_match_claim, jwt.claims)
    }
  end

  if not consumer then
    return unmatched(
      conf,
      "no Kong consumer matched the configured claim",
      conf.consumer_match_claim,
      jwt.claims
    )
  end

  set_consumer(consumer, {id = jwt.claims.sub}, nil)
  return true
end

ConsumerMatch.custom_id_cache_key = custom_id_cache_key

return ConsumerMatch
