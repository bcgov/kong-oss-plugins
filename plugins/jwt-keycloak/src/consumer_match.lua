local ConsumerMatch = {}

local UNMATCHED_CONSUMER_MESSAGE = "Unable to match token to a Kong consumer"

local function unmatched(conf, reason)
  kong.log.debug("Consumer match failed: " .. reason)

  if conf.consumer_match_ignore_not_found then
    return true
  end

  return false, {
    status = 401,
    message = UNMATCHED_CONSUMER_MESSAGE
  }
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
    return unmatched(conf, invalid_reason)
  end

  local consumer, err
  if conf.consumer_match_claim_custom_id then
    consumer, err = kong.cache:get(
      custom_id_cache_key(consumer_id),
      nil,
      load_consumer_by_custom_id,
      consumer_id,
      true
    )
  else
    consumer, err = kong.cache:get(
      kong.db.consumers:cache_key(consumer_id),
      nil,
      kong.client.load_consumer,
      consumer_id,
      true
    )
  end

  if err then
    kong.log.err("Consumer lookup failed for the configured match claim")
  end

  if not consumer then
    return unmatched(conf, "no Kong consumer matched the configured claim")
  end

  set_consumer(consumer, {id = jwt.claims.sub}, nil)
  return true
end

ConsumerMatch.custom_id_cache_key = custom_id_cache_key

return ConsumerMatch
