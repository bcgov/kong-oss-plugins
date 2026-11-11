local jwks = require "jwks"
local json = require "cjson"

local function daos(entities, options)
  options = options or {}
  local function iterate()
    local index = 0
    return function()
      index = index + 1
      if options.iterator_error and index == 2 then return nil, "database secret" end
      return entities[index]
    end
  end
  return {each = iterate, each_for_set = iterate}, {
    select_by_name = function()
      if options.lookup_error then return nil, "database secret" end
      if options.missing then return nil end
      return {id = "set-id"}
    end
  }
end
local public = {kty = "RSA", n = "public-n", e = "AQAB", kid = "public"}
local function stored(value) return {jwk = json.encode(value)} end
local function build(entities, options, name)
  local keys, sets = daos(entities, options)
  return jwks.build(keys, sets, name)
end

describe("trust-registry publication and failure contract", function()
  -- [Verifies: trust-registry.keyset-selection.empty-set]
  it("encodes an empty keys array", function()
    local body, status = build({})
    assert.equals(200, status)
    assert.equals('{"keys":[]}', json.encode(body))
  end)

  -- [Verifies: trust-registry.stored-jwk.private-members]
  it("allowlists public members and preserves supported metadata", function()
    local key = {kty = "RSA", n = "public-n", e = "AQAB", kid = "public", use = "enc",
      d = "secret", p = "secret", q = "secret", dp = "secret", dq = "secret",
      qi = "secret", oth = {{r = "secret"}}, extension = {secret = "secret"}}
    local body, status = build({stored(key)})
    assert.equals(200, status)
    assert.same({keys = {{kty = "RSA", n = "public-n", e = "AQAB", kid = "public", use = "enc"}}}, body)
    assert.is_nil(json.encode(body):find("secret", 1, true))
  end)

  -- [Verifies: trust-registry.stored-jwk.symmetric-key]
  it("omits symmetric keys without losing public siblings", function()
    local body, status = build({stored({kty = "oct", k = "secret"}), stored(public)})
    assert.equals(200, status)
    assert.same({keys = {public}}, body)
  end)

  -- [Verifies: trust-registry.stored-jwk.invalid-parameters]
  it("omits nonobjects, unsupported types and incomplete public keys", function()
    for _, invalid in ipairs({"null", "false", '"string"', "42", "[]",
      '{"kty":"unknown"}', '{"kty":"RSA","n":"n"}',
      '{"kty":"EC","crv":"P-256","x":"x"}', '{"kty":"OKP","crv":"Ed25519"}'}) do
      local body, status = build({{jwk = invalid}, stored(public)})
      assert.equals(200, status)
      assert.same({keys = {public}}, body)
    end
  end)

  -- [Verifies: trust-registry.pem-publication.conversion-failure]
  it("omits malformed PEM and publishes a valid sibling", function()
    local body, status = build({{pem = {public_key = "not a PEM"}, kid = "bad"}, stored(public)})
    assert.equals(200, status)
    assert.same({keys = {public}}, body)
  end)

  -- [Verifies: trust-registry.failure-behavior.lookup-error]
  it("distinguishes lookup failure from absence without leaking details", function()
    for _, name in ipairs({"captured", "configured"}) do
      local body, status = build({}, {lookup_error = true}, name)
      assert.equals(500, status)
      assert.same({message = "Internal server error"}, body)
    end
    local body, status = build({}, {missing = true}, "absent")
    assert.equals(404, status)
    assert.same({message = "Key set not found"}, body)
  end)

  -- [Verifies: trust-registry.failure-behavior.iterator-error]
  it("discards partial results on enumeration failure", function()
    for _, name in ipairs({false, "selected"}) do
      local body, status = build({stored(public)}, {iterator_error = true}, name)
      assert.equals(500, status)
      assert.same({message = "Internal server error"}, body)
      assert.is_nil(body.keys)
    end
  end)

  -- [Verifies: trust-registry.failure-behavior.invalid-jwk]
  it("skips invalid JSON while retaining valid siblings", function()
    local body, status = build({{jwk = "not json"}, stored(public)})
    assert.equals(200, status)
    assert.same({keys = {public}}, body)
    body, status = build({{jwk = "not json"}})
    assert.equals(200, status)
    assert.equals('{"keys":[]}', json.encode(body))
  end)
end)

describe("additional public key types", function()
  it("removes EC and OKP private material while preserving public coordinates", function()
    for _, value in ipairs({
      {kty = "EC", crv = "P-256", x = "x", y = "y", d = "secret"},
      {kty = "OKP", crv = "Ed25519", x = "x", d = "secret"},
    }) do
      local body, status = build({stored(value)})
      value.d = nil
      assert.equals(200, status)
      assert.same({keys = {value}}, body)
    end
  end)
end)
