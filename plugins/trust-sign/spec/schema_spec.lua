-- Clean-room schema tests generated from openspec/specs/trust-sign/spec.md
-- (Configuration schema requirement). Validated with Kong's own schema engine.

local Schema = require "kong.db.schema"
local schema_def = require "schema"
local xfail = require "xfail"

local config_def
for _, field in ipairs(schema_def.fields) do
  if field.config then
    config_def = field.config
    break
  end
end
local config_schema = assert(Schema.new(assert(config_def, "schema missing config field")))

-- Canonical valid config, built entirely from the spec's Configuration schema
-- requirement. Key path is the shared fixture mount used by the compose stack.
local function valid_config(overrides)
  local config = {
    keyid = "rsa-2048",
    private_key_location = "/tmp/kong/fixtures/keys/rsa-2048.pem",
    signature_header_key = "X-Edge-Token",
    alg = "RS256",
    direction = "request",
    jwks_uri = "https://jwks.example.test/keys.json",
  }
  for k, v in pairs(overrides or {}) do
    config[k] = v
  end
  return config
end

describe("trust-sign configuration schema", function()

  -- [Verifies: trust-sign.request-manifest-signing.signature-header-key-defaults-to-x-edge-token]
  it("accepts a canonical valid config and defaults signature_header_key to X-Edge-Token", function()
    local ok, err = config_schema:validate(valid_config())
    assert.is_truthy(ok, "canonical valid config rejected: " .. tostring(require("cjson").encode(err or {})))

    -- schema half of the scenario: omitting signature_header_key applies the default
    local config = valid_config({ signature_header_key = nil })
    local processed = config_schema:process_auto_fields(config, "insert")
    local ok2, err2 = config_schema:validate(processed)
    assert.is_truthy(ok2, "config without signature_header_key rejected: " .. tostring(require("cjson").encode(err2 or {})))
    assert.equal("X-Edge-Token", processed.signature_header_key)
  end)

  -- [Verifies: trust-sign.configuration-schema.required-fields]
  -- pending — APS-4798 (private_key_location / alg remain required; keyid is
  -- optional when keyset_name is set)
  it("rejects configs missing private_key_location or alg (xfail APS-4798)", function()
    xfail("APS-4798", function()
      for _, missing in ipairs({ "private_key_location", "alg" }) do
        local config = valid_config({ [missing] = nil })
        local processed = config_schema:process_auto_fields(config, "insert")
        local ok, err = config_schema:validate(processed)
        assert.is_falsy(ok, "config missing " .. missing .. " was accepted")
        assert.is_truthy(err and err[missing], "no validation error reported for missing " .. missing)
      end
    end)
  end)

  it("accepts keyset_name without an explicit keyid", function()
    local config = valid_config({ keyid = nil, keyset_name = "sdx.edge.myrg.dev" })
    local processed = config_schema:process_auto_fields(config, "insert")
    local ok, err = config_schema:validate(processed)
    assert.is_truthy(ok, "keyset_name-only config rejected: " .. tostring(require("cjson").encode(err or {})))
  end)

  it("rejects configs that omit both keyid and keyset_name", function()
    local config = valid_config({ keyid = nil, keyset_name = nil })
    local processed = config_schema:process_auto_fields(config, "insert")
    local ok = config_schema:validate(processed)
    assert.is_falsy(ok, "config missing both keyid and keyset_name was accepted")
  end)

  -- [Verifies: trust-sign.configuration-schema.enumerated-fields]
  it("rejects direction and alg values outside their allowed sets", function()
    local processed = config_schema:process_auto_fields(valid_config({ direction = "sideways" }), "insert")
    local ok, err = config_schema:validate(processed)
    assert.is_falsy(ok, "direction=sideways was accepted")
    assert.is_truthy(err and err.direction, "no validation error reported for direction")

    processed = config_schema:process_auto_fields(valid_config({ alg = "HS256" }), "insert")
    local ok2, err2 = config_schema:validate(processed)
    assert.is_falsy(ok2, "alg=HS256 was accepted")
    assert.is_truthy(err2 and err2.alg, "no validation error reported for alg")
  end)
end)
