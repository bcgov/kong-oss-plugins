local Schema = require "kong.db.schema"
local schema_def = require "schema"

local config_def
for _, field in ipairs(schema_def.fields) do
  if field.config then
    config_def = field.config
    break
  end
end

local config_schema = assert(Schema.new(assert(config_def, "schema missing config field")))

local function canonical_config(overrides)
  local config = {
    private_key_location = "/tmp/kong/fixtures/keys/rsa-2048.pem",
    client_id = "schema-client",
    token_endpoint = "https://tokens.example.test/exchange",
  }

  for key, value in pairs(overrides or {}) do
    config[key] = value
  end

  return config
end

describe("token-exchange configuration schema", function()
  -- [Verifies: token-exchange.configuration-schema.required-fields]
  it("rejects each missing required field", function()
    for _, field in ipairs({ "private_key_location", "client_id", "token_endpoint" }) do
      local config = canonical_config()
      config[field] = nil

      local ok, err = config_schema:validate(config)
      assert.is_falsy(ok)
      assert.is_truthy(err[field], "expected validation error for " .. field)
    end
  end)

  -- [Verifies: token-exchange.configuration-schema.enumerated-algorithms]
  it("rejects an algorithm outside the supported enumeration", function()
    local ok, err = config_schema:validate(canonical_config({ algorithm = "HS256" }))
    assert.is_falsy(ok)
    assert.is_truthy(err.algorithm)
  end)

  -- [Verifies: token-exchange.configuration-schema.canonical-config-accepted]
  it("accepts canonical configuration and applies defaults", function()
    local config = canonical_config()
    local processed, err = config_schema:process_auto_fields(config, "insert")
    assert.is_nil(err)
    assert.is_table(processed)

    local ok, validation_err = config_schema:validate(processed)
    assert.is_truthy(ok)
    assert.is_nil(validation_err)
    assert.equals("RS256", processed.algorithm)
    assert.equals(60, processed.expiration)
    assert.same({}, processed.scopes)
    assert.equals(10000, processed.timeout)
  end)

  it("accepts keyset_name without an explicit key_id", function()
    local ok, err = config_schema:validate(canonical_config({
      keyset_name = "sdx.edge.myrg.dev",
    }))
    assert.is_truthy(ok, "keyset_name-only config rejected")
    assert.is_nil(err)
  end)

  -- [Verifies: token-exchange.configuration-schema.nonpositive-expiration-accepted]
  it("rejects zero and negative expiration values", function()
    for _, expiration in ipairs({ 0, -1 }) do
      local ok, err = config_schema:validate(canonical_config({ expiration = expiration }))
      assert.is_falsy(ok)
      assert.is_truthy(err.expiration)
    end
  end)
end)
