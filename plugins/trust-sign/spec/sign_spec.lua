-- Clean-room unit tests generated from openspec/specs/trust-sign/spec.md.
-- The Private key resolution requirement seams `get_private_key_location`
-- (require "sign") for unit testing the KONG_SIGNING_CERT_KEY override,
-- which is process-global in the shared compose stack and therefore not
-- wire-testable there.

local ENV_VAR = "KONG_SIGNING_CERT_KEY"

local real_getenv = os.getenv

local function load_sign_with_env(env_value)
  -- Stub os.getenv before (re)loading the module, in case the value is
  -- captured at load time rather than per call.
  os.getenv = function(name)  -- luacheck: ignore
    if name == ENV_VAR then
      return env_value
    end
    return real_getenv(name)
  end
  package.loaded["sign"] = nil
  return require "sign"
end

describe("trust-sign private key resolution (sign.get_private_key_location)", function()

  after_each(function()
    os.getenv = real_getenv  -- luacheck: ignore
    package.loaded["sign"] = nil
  end)

  -- [Verifies: trust-sign.private-key-resolution.env-var-overrides-configuration]
  it("uses KONG_SIGNING_CERT_KEY over config.private_key_location when set", function()
    local conf = { private_key_location = "/tmp/kong/fixtures/keys/rsa-2048.pem" }

    -- baseline: env unset resolves to the configured location
    local sign = load_sign_with_env(nil)
    assert.equal("/tmp/kong/fixtures/keys/rsa-2048.pem", sign.get_private_key_location(conf))

    -- env set overrides the configured location for all plugin instances
    sign = load_sign_with_env("/env/override/signing.pem")
    assert.equal("/env/override/signing.pem", sign.get_private_key_location(conf))
  end)
end)
