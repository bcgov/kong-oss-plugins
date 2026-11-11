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

describe("trust-verify-signature schema", function()

  -- [Verifies: trust-verify-signature.configuration-schema.canonical-valid-config]
  it("accepts a canonical valid config", function()
    local ok, err = config_schema:validate({
      signature_header_key = "X-Edge-Token",
      allowed_jwks_uri_prefix = { "https://jwks.example.com" },
      direction = "request",
      manifest_type = "signature-only",
    })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  -- [Verifies: trust-verify-signature.configuration-schema.enumerated-fields]
  it("rejects an out-of-set direction", function()
    local ok, err = config_schema:validate({
      allowed_jwks_uri_prefix = { "https://jwks.example.com" },
      direction = "sideways",
    })
    assert.is_falsy(ok)
    assert.is_truthy(err.direction)
  end)

  -- [Verifies: trust-verify-signature.configuration-schema.enumerated-fields]
  it("rejects an out-of-set manifest_type", function()
    local ok, err = config_schema:validate({
      allowed_jwks_uri_prefix = { "https://jwks.example.com" },
      manifest_type = "not-a-real-type",
    })
    assert.is_falsy(ok)
    assert.is_truthy(err.manifest_type)
  end)

  -- [Verifies: trust-verify-signature.configuration-schema.signature-header-key-defaults-to-x-edge-token]
  it("defaults signature_header_key to X-Edge-Token when omitted", function()
    local processed = config_schema:process_auto_fields({
      allowed_jwks_uri_prefix = { "https://jwks.example.com" },
    }, "insert")
    local ok, err = config_schema:validate(processed)
    assert.is_nil(err)
    assert.is_truthy(ok)
    assert.equals("X-Edge-Token", processed.signature_header_key)
  end)

  -- [Verifies: trust-verify-signature.configuration-schema.allowed-jwks-uri-prefix-required]
  it("rejects a config missing allowed_jwks_uri_prefix", function()
    local ok, err = config_schema:validate({
      signature_header_key = "X-Edge-Token",
    })
    assert.is_falsy(ok)
    assert.is_truthy(err.allowed_jwks_uri_prefix)
  end)

end)
