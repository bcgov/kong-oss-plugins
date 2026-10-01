local consumer_match = require("kong.plugins.jwt-keycloak.consumer_match")

local UNMATCHED_CONSUMER_ERROR = {
  status = 401,
  message = "Unable to match token to a Kong consumer"
}

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

    _G.kong = {
      cache = {
        get = function(_, cache_key, _, loader, consumer_id, resurrect_ttl)
          table.insert(cache_calls, {
            cache_key = cache_key,
            consumer_id = consumer_id,
            resurrect_ttl = resurrect_ttl
          })
          return loader(consumer_id)
        end
      },
      client = {
        load_consumer = function(consumer_id)
          table.insert(username_lookups, consumer_id)
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
      {cache_key = "custom_id_key_client-a", consumer_id = "client-a", resurrect_ttl = true}
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
    assert.same({"client-a"}, username_lookups)
    assert.same({}, custom_id_lookups)
    assert.same({
      {cache_key = "consumer_key_client-a", consumer_id = "client-a", resurrect_ttl = true}
    }, cache_calls)
    assert.same(lookup_result, authenticated.consumer)
  end)

  -- [Verifies: APS-4990 unknown consumer response]
  it("returns a stable 401 error without exposing the lookup value", function()
    lookup_error = "database failed while looking up sensitive-client"

    local ok, err = match({sub = "subject", azp = "sensitive-client"})

    assert.is_false(ok)
    assert.same(UNMATCHED_CONSUMER_ERROR, err)
    assert.same({"Consumer lookup failed for the configured match claim"}, error_logs)
    assert.is_nil(table.concat(debug_logs, " "):find("sensitive-client", 1, true))
    assert.is_nil(table.concat(error_logs, " "):find("sensitive-client", 1, true))
  end)

  -- [Verifies: APS-4990 ignore-not-found compatibility]
  it("continues without lookup when an unusable claim is configured to be ignored", function()
    local ok, err = match(
      {sub = "subject", azp = {"invalid"}},
      {consumer_match_ignore_not_found = true}
    )

    assert.is_true(ok)
    assert.is_nil(err)
    assert.same({}, cache_calls)
    assert.same({}, authenticated)
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
end)
