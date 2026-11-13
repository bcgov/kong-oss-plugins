local Schema = require "kong.db.schema"
local definition = require "schema"

local config
for _, field in ipairs(definition.fields) do
  if field.config then
    config = field.config
  end
end
local schema = assert(Schema.new(assert(config)))

describe("trust-registry spec contract", function()
  -- [Verifies: trust-registry.configuration-schema.valid-config]
  it("accepts empty config", function()
    assert.is_truthy(schema:validate({}))
  end)

  -- [Verifies: trust-registry.configuration-schema.named-config]
  it("accepts named keyset", function()
    assert.is_truthy(schema:validate({ key_set = "registry-example" }))
  end)

  -- [Verifies: trust-registry.pem-conversion.invalid-pem]
  it("returns a parsing error for invalid PEM", function()
    local key, err = require("pem_to_jwks").public_key_to_jwks("not a PEM", "bad")
    assert.is_nil(key)
    assert.is_string(err)
    assert.matches("^Failed to load key: ", err)
    assert.is_true(#err > #"Failed to load key: ")
  end)
end)
