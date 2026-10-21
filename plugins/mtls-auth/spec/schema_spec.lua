-- Schema tests for mtls-auth, generated clean-room from
-- openspec/specs/mtls-auth/spec.md (Configuration schema requirement).

local PLUGIN_NAME = "mtls-auth"

local Schema = require "kong.db.schema"
local schema_def = require "schema"

-- Config subschema, validated with Kong's own validator.
local config_def
for _, field in ipairs(schema_def.fields) do
  if field.config then
    config_def = field.config
    break
  end
end
local config_schema = assert(Schema.new(assert(config_def, "schema missing config field")))

-- Full plugin entity schema for scope/protocol validation. The plugins
-- entity has foreign references, so register those core entities first
-- (dependency order: certificates before services before routes).
local Entity = require "kong.db.schema.entity"
for _, entity in ipairs({ "certificates", "consumers", "services", "routes" }) do
  assert(Entity.new(require("kong.db.schema.entities." .. entity)))
end
local plugins_definition = require "kong.db.schema.entities.plugins"
local plugins_schema = assert(Entity.new(plugins_definition))
assert(plugins_schema:new_subschema(PLUGIN_NAME, schema_def))

--- Validate a plugin entity (name auto-filled) the way an insert would.
local function validate_plugin_entity(entity)
  entity.name = PLUGIN_NAME
  local processed = plugins_schema:process_auto_fields(entity, "insert")
  return plugins_schema:validate_insert(processed)
end

describe("mtls-auth configuration schema", function()

  -- [Verifies: mtls-auth.configuration-schema.minimal-config-valid]
  it("accepts an empty config and defaults error_response_code to 401", function()
    local processed = config_schema:process_auto_fields({}, "insert")
    assert.equal(401, processed.error_response_code)
    local ok, err = config_schema:validate(processed)
    assert.is_nil(err)
    assert.is_truthy(ok)

    -- The same minimal config is accepted as a full plugin entity on https.
    local entity_ok, entity_err = validate_plugin_entity({
      config = {},
      protocols = { "https" },
    })
    assert.is_nil(entity_err)
    assert.is_truthy(entity_ok)
  end)

  -- [Verifies: mtls-auth.configuration-schema.no-consumer-scope]
  it("rejects consumer-scoped configuration", function()
    local ok, err = validate_plugin_entity({
      config = {},
      protocols = { "https" },
      consumer = { id = "cbb297c0-a26c-4b8d-b442-cf3f1a3ea1f0" },
    })
    assert.is_falsy(ok)
    assert.is_truthy(err)
    assert.is_truthy(err.consumer)
  end)

  -- [Verifies: mtls-auth.configuration-schema.non-https-protocol-rejected]
  it("rejects any protocols set containing a non-https protocol", function()
    for _, protocol in ipairs({ "http", "grpc", "grpcs" }) do
      local ok, err = validate_plugin_entity({
        config = {},
        protocols = { protocol },
      })
      assert.is_falsy(ok, "expected protocol '" .. protocol .. "' to be rejected")
      assert.is_truthy(err)
      assert.is_truthy(err.protocols)
    end

    -- A mixed set containing https alongside another protocol is still rejected.
    local ok, err = validate_plugin_entity({
      config = {},
      protocols = { "https", "http" },
    })
    assert.is_falsy(ok)
    assert.is_truthy(err)
    assert.is_truthy(err.protocols)
  end)

  -- [Verifies: mtls-auth.configuration-schema.error-response-code-below-400]
  it("rejects error_response_code 399", function()
    local ok, err = config_schema:validate({ error_response_code = 399 })
    assert.is_falsy(ok)
    assert.is_truthy(err)
    assert.is_truthy(err.error_response_code)
  end)

  -- [Verifies: mtls-auth.configuration-schema.error-response-code-above-599]
  it("rejects error_response_code 600", function()
    local ok, err = config_schema:validate({ error_response_code = 600 })
    assert.is_falsy(ok)
    assert.is_truthy(err)
    assert.is_truthy(err.error_response_code)
  end)

  -- [Verifies: mtls-auth.configuration-schema.error-response-code-must-be-integer]
  it("rejects a non-integer error_response_code", function()
    local ok, err = config_schema:validate({ error_response_code = 401.5 })
    assert.is_falsy(ok)
    assert.is_truthy(err)
    assert.is_truthy(err.error_response_code)
  end)

end)
