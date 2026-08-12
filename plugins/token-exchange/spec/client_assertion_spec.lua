local ENV_KEY_PATH = "/work/testsuite/local/kong/fixtures/keys/rsa-2048.pem"
local CONFIG_KEY_PATH = "/work/testsuite/local/kong/fixtures/keys/ec-p256.pem"
local SIGNER_MODULE = "kong.plugins.trust-sign.sign"

local function read_file(path)
  local file = assert(io.open(path, "rb"))
  local contents = assert(file:read("*a"))
  assert(file:close())
  return contents
end

describe("token-exchange private key environment override", function()
  local original_getenv
  local resolved_key_path

  before_each(function()
    original_getenv = os.getenv
    os.getenv = function(name)
      if name == "KONG_SIGNING_CERT_KEY" then
        return ENV_KEY_PATH
      end
      return original_getenv(name)
    end

    package.preload[SIGNER_MODULE] = function()
      return assert(loadfile("../trust-sign/src/sign.lua"))()
    end
    package.loaded[SIGNER_MODULE] = nil
    package.loaded.client_assertion = nil
  end)

  after_each(function()
    os.getenv = original_getenv
    package.preload[SIGNER_MODULE] = nil
    package.loaded[SIGNER_MODULE] = nil
    package.loaded.client_assertion = nil
  end)

  -- [Verifies: token-exchange.private-key-resolution.environment-override-ignored]
  it("uses the key path selected by the real KONG_SIGNING_CERT_KEY resolver", function()
    local signer = assert(require(SIGNER_MODULE))
    local real_get_private_key_location = assert(signer.get_private_key_location)
    signer.get_private_key_location = function(config)
      resolved_key_path = real_get_private_key_location(config)
      return resolved_key_path
    end
    signer.get_kong_key = function(_, path)
      return read_file(path)
    end

    local create_client_assertion = assert(require("client_assertion").create_client_assertion)
    local assertion = assert(create_client_assertion({
      private_key_location = CONFIG_KEY_PATH,
      client_id = "environment-override-client",
      token_endpoint = "https://tokens.example.test/exchange",
      algorithm = "RS256",
      expiration = 60,
    }))

    assert.matches("^[^.]+%.[^.]+%.[^.]+$", assertion)
    assert.equals(ENV_KEY_PATH, resolved_key_path)
  end)
end)
