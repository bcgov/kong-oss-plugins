local consumer_match = require("kong.plugins.jwt-keycloak.consumer_match")

local UNMATCHED_CONSUMER_ERROR = {
  status = 401,
  message = "Unable to match token to a Kong consumer",
  log_reason = "configured claim is missing or is not a non-empty string",
  log_attributes = {consumer_match_claim = "azp"}
}

local LOOKUP_FAILURE_MESSAGE = "An unexpected error occurred during authentication"

local function default_config(overrides)
  local config = {
    consumer_match_claim = "azp",
    consumer_match_claim_custom_id = true,
    consumer_match_ignore_not_found = false
  }

  for key, value in pairs(overrides or {}) do
    config[key] = value
  end

  return config
end

describe("jwt-keycloak consumer matching", function()
  local cache_calls
  local custom_id_lookups
  local username_cache_keys
  local username_lookups
  local authenticated
  local debug_logs
  local error_logs
  local lookup_result
  local lookup_error
  local cache_results

  before_each(function()
    cache_calls = {}
    custom_id_lookups = {}
    username_cache_keys = {}
    username_lookups = {}
    authenticated = {}
    debug_logs = {}
    error_logs = {}
    lookup_result = nil
    lookup_error = nil
    cache_results = {}

    _G.kong = {
      cache = {
        get = function(_, cache_key, _, loader, consumer_id, search_by_username)
          table.insert(cache_calls, {
            cache_key = cache_key,
            consumer_id = consumer_id,
            search_by_username = search_by_username
          })
          local cached = cache_results[cache_key]
          if cached then
            return cached.value, cached.error
          end
          return loader(consumer_id, search_by_username)
        end
      },
      client = {
        load_consumer = function(consumer_id, search_by_username)
          table.insert(username_lookups, {
            consumer_id = consumer_id,
            search_by_username = search_by_username
          })
          if not search_by_username and not consumer_id:match("^[0-9a-f]+%-[0-9a-f%-]+$") then
            return nil, "consumer id is not a UUID"
          end
          return lookup_result, lookup_error
        end
      },
      db = {
        consumers = {
          cache_key = function(_, consumer_id)
            table.insert(username_cache_keys, consumer_id)
            return "consumer_key_" .. consumer_id
          end,
          select_by_custom_id = function(_, consumer_id)
            table.insert(custom_id_lookups, consumer_id)
            return lookup_result, lookup_error
          end
        }
      },
      log = {
        debug = function(message)
          table.insert(debug_logs, message)
        end,
        err = function(message)
          table.insert(error_logs, message)
        end
      }
    }
  end)

  local function match(claims, overrides)
    return consumer_match.match(
      default_config(overrides),
      {claims = claims},
      function(consumer, credential, token)
        authenticated = {
          consumer = consumer,
          credential = credential,
          token = token
        }
      end
    )
  end

  local function assert_rejected_without_lookup(claims, overrides)
    local ok, err = match(claims, overrides)

    assert.is_false(ok)
    assert.same(UNMATCHED_CONSUMER_ERROR, err)
    assert.same({}, cache_calls)
    assert.same({}, custom_id_lookups)
    assert.same({}, username_cache_keys)
    assert.same({}, username_lookups)
  end

  -- [Verifies: APS-4990 missing and blank match claims]
  it("rejects missing, empty, and whitespace-only claims before lookup", function()
    assert_rejected_without_lookup({sub = "subject"})
    assert_rejected_without_lookup({sub = "subject", azp = ""})
    assert_rejected_without_lookup({sub = "subject", azp = " \t\n"})
  end)

  -- [Verifies: APS-4990 non-string match claims]
  it("rejects non-string claims before lookup", function()
    for _, value in ipairs({42, true, {client = "sensitive-client"}}) do
      assert_rejected_without_lookup({sub = "subject", azp = value})
    end
  end)

  -- [Verifies: APS-4990 custom_id matching]
  it("loads a valid custom_id and authenticates its consumer", function()
    lookup_result = {id = "consumer-id", custom_id = "client-a"}

    local ok, err = match({sub = "subject-a", azp = "client-a"})

    assert.is_true(ok)
    assert.is_nil(err)
    assert.same({"client-a"}, custom_id_lookups)
    assert.same({}, username_cache_keys)
    assert.same({
      {cache_key = "custom_id_key_client-a", consumer_id = "client-a"}
    }, cache_calls)
    assert.same(lookup_result, authenticated.consumer)
    assert.same({id = "subject-a"}, authenticated.credential)
    assert.is_nil(authenticated.token)
  end)

  -- [Verifies: APS-4990 username compatibility]
  it("preserves id and username consumer matching", function()
    lookup_result = {id = "consumer-id", username = "client-a"}

    local ok, err = match(
      {sub = "subject-a", azp = "client-a"},
      {consumer_match_claim_custom_id = false}
    )

    assert.is_true(ok)
    assert.is_nil(err)
    assert.same({"client-a"}, username_cache_keys)
    assert.same({{consumer_id = "client-a", search_by_username = true}}, username_lookups)
    assert.same({}, custom_id_lookups)
    assert.same({
      {cache_key = "consumer_key_client-a", consumer_id = "client-a", search_by_username = true}
    }, cache_calls)
    assert.same(lookup_result, authenticated.consumer)
  end)

  -- [Verifies: APS-4990 unknown consumer response]
  it("returns a generic 500 and records the cache or database error", function()
    lookup_error = "database failed while looking up sensitive-client"

    local ok, err = match({
      sub = "subject",
      azp = "sensitive-client",
      client_id = "client-alias"
    })

    assert.is_false(ok)
    assert.same(500, err.status)
    assert.same(LOOKUP_FAILURE_MESSAGE, err.message)
    assert.same("consumer lookup failed: " .. lookup_error, err.log_reason)
    assert.same({
      consumer_match_claim = "azp",
      azp = "sensitive-client",
      client_id = "client-alias"
    }, err.log_attributes)
    assert.same({"Consumer lookup failed for the configured match claim: " .. lookup_error}, error_logs)

    ok, err = match(
      {sub = "subject", azp = "sensitive-client"},
      {consumer_match_ignore_not_found = true}
    )
    assert.is_false(ok)
    assert.same(500, err.status)
  end)

  -- [Verifies: APS-4990 ignore-not-found compatibility]
  it("rejects an unusable claim even when an unknown consumer would be ignored", function()
    assert_rejected_without_lookup(
      {sub = "subject", azp = {"invalid"}},
      {consumer_match_ignore_not_found = true}
    )
  end)

  -- [Verifies: APS-4990 ignore-not-found compatibility]
  it("continues when an unknown consumer is configured to be ignored", function()
    local ok, err = match(
      {sub = "subject", azp = "unknown-client"},
      {consumer_match_ignore_not_found = true}
    )

    assert.is_true(ok)
    assert.is_nil(err)
    assert.same({"unknown-client"}, custom_id_lookups)
    assert.same({}, authenticated)
  end)

  -- [Verifies: APS-4990 cached consumer compatibility]
  it("authenticates a cached consumer without calling the loader", function()
    local cached_consumer = {id = "cached-consumer", custom_id = "client-a"}
    cache_results["custom_id_key_client-a"] = {value = cached_consumer}

    local ok, err = match({sub = "subject-a", azp = "client-a"})

    assert.is_true(ok)
    assert.is_nil(err)
    assert.same({}, custom_id_lookups)
    assert.same({}, username_lookups)
    assert.same(cached_consumer, authenticated.consumer)
  end)

  -- [Verifies: APS-4990 cached not-found compatibility]
  it("handles a cached not-found without calling the loader", function()
    cache_results["custom_id_key_unknown-client"] = {}

    local ok, err = match({sub = "subject", azp = "unknown-client"})

    assert.is_false(ok)
    assert.same(401, err.status)
    assert.same("Unable to match token to a Kong consumer", err.message)
    assert.same({}, custom_id_lookups)

    ok, err = match(
      {sub = "subject", azp = "unknown-client"},
      {consumer_match_ignore_not_found = true}
    )

    assert.is_true(ok)
    assert.is_nil(err)
    assert.same({}, custom_id_lookups)
  end)
end)
