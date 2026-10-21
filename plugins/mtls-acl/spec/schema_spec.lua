-- Schema validation tests for mtls-acl, driven by Kong's own validator.
--
-- Validation goes through the `plugins` entity with mtls-acl registered as a
-- subschema, so entity-level rules (consumer scope, protocols, allow/deny
-- exclusivity entity checks) are exercised exactly as Kong applies them.

local Entity = require "kong.db.schema.entity"
local cjson = require "cjson"

local schema_def = require "schema"

-- Register the schemas the plugins entity references so its foreign-key
-- fields resolve outside a running Kong.
for _, name in ipairs({
  "workspaces",
  "key_sets",
  "keys",
  "certificates",
  "ca_certificates",
  "consumers",
  "services",
  "routes",
}) do
  local ok, def = pcall(require, "kong.db.schema.entities." .. name)
  if ok then
    pcall(Entity.new, def)
  end
end

local plugins_schema = assert(Entity.new(require "kong.db.schema.entities.plugins"))
assert(plugins_schema:new_subschema("mtls-acl", schema_def))

local UUID = "cbb297c0-a956-486d-ad1d-f9b12df9fbfb"

--- Validate a plugin entity the way an insert would be validated.
-- @param overrides fields merged over { id, name = "mtls-acl", enabled }
-- @return ok, err from Kong's validator
local function validate(overrides)
  local entity = {
    id = UUID,
    name = "mtls-acl",
    enabled = true,
  }
  for k, v in pairs(overrides) do
    entity[k] = v
  end
  local entity_to_insert, auto_err = plugins_schema:process_auto_fields(entity, "insert")
  if not entity_to_insert then
    return nil, auto_err
  end
  return plugins_schema:validate_insert(entity_to_insert)
end

local function err_string(err)
  return cjson.encode(err or {})
end

describe("mtls-acl schema", function()

  -- [Verifies: mtls-acl.configuration-schema.required-field]
  it("rejects config omitting certificate_attribute", function()
    local ok, err = validate({
      config = { allow = { "Alice Example" } },
    })
    assert.is_falsy(ok)
    assert.is_truthy(err)
    assert.matches("certificate_attribute", err_string(err), nil, true)
  end)

  -- [Verifies: mtls-acl.configuration-schema.invalid-attribute-rejected]
  it("rejects certificate_attribute outside the enumerated list", function()
    local ok, err = validate({
      config = {
        certificate_attribute = "x-client-cert-fp",
        allow = { "Alice Example" },
      },
    })
    assert.is_falsy(ok)
    assert.is_truthy(err)
    assert.matches("certificate_attribute", err_string(err), nil, true)
  end)

  -- [Verifies: mtls-acl.configuration-schema.both-allow-and-deny-rejected]
  it("rejects config with both allow and deny set", function()
    local ok, err = validate({
      config = {
        certificate_attribute = "common_name",
        allow = { "Alice Example" },
        deny = { "Mallory Example" },
      },
    })
    assert.is_falsy(ok)
    assert.is_truthy(err)
  end)

  -- [Verifies: mtls-acl.configuration-schema.neither-allow-nor-deny-rejected]
  it("rejects config with neither allow nor deny set", function()
    local ok, err = validate({
      config = { certificate_attribute = "common_name" },
    })
    assert.is_falsy(ok)
    assert.is_truthy(err)
  end)

  -- [Verifies: mtls-acl.configuration-schema.empty-allow-rejected]
  it("rejects an explicitly empty allow array", function()
    local ok, err = validate({
      config = {
        certificate_attribute = "common_name",
        allow = setmetatable({}, cjson.array_mt),
      },
    })
    assert.is_falsy(ok)
    assert.is_truthy(err)
  end)

  -- [Verifies: mtls-acl.configuration-schema.empty-deny-rejected]
  it("rejects an explicitly empty deny array", function()
    local ok, err = validate({
      config = {
        certificate_attribute = "common_name",
        deny = setmetatable({}, cjson.array_mt),
      },
    })
    assert.is_falsy(ok)
    assert.is_truthy(err)
  end)

  -- [Verifies: mtls-acl.configuration-schema.canonical-config-valid]
  it("accepts a canonical valid config for every enumerated attribute", function()
    local attributes = {
      "cert",
      "fingerprint",
      "serial",
      "issuer_dn",
      "subject_dn",
      "common_name",
      "organization",
    }
    for _, attribute in ipairs(attributes) do
      local ok, err = validate({
        config = {
          certificate_attribute = attribute,
          allow = { "Alice Example" },
        },
      })
      assert.is_truthy(ok, attribute .. " (allow): " .. err_string(err))
      assert.is_nil(err)

      ok, err = validate({
        config = {
          certificate_attribute = attribute,
          deny = { "Mallory Example" },
        },
      })
      assert.is_truthy(ok, attribute .. " (deny): " .. err_string(err))
      assert.is_nil(err)
    end
  end)

  -- [Verifies: mtls-acl.configuration-schema.no-consumer-scope]
  it("rejects consumer-scoped configuration", function()
    local ok, err = validate({
      consumer = { id = UUID },
      config = {
        certificate_attribute = "common_name",
        allow = { "Alice Example" },
      },
    })
    assert.is_falsy(ok)
    assert.is_truthy(err)
    assert.matches("consumer", err_string(err), nil, true)
  end)

  -- [Verifies: mtls-acl.configuration-schema.non-https-protocol-rejected]
  it("rejects a protocols set containing a non-https protocol", function()
    local ok, err = validate({
      protocols = { "http" },
      config = {
        certificate_attribute = "common_name",
        allow = { "Alice Example" },
      },
    })
    assert.is_falsy(ok)
    assert.is_truthy(err)
    assert.matches("protocols", err_string(err), nil, true)
  end)
end)
