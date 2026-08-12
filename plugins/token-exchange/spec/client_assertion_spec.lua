local ENV_KEY_PATH = "/work/testsuite/local/kong/fixtures/keys/rsa-2048.pem"
local CONFIG_KEY_PATH = "/work/testsuite/local/kong/fixtures/keys/ec-p256.pem"
local SIGNER_MODULE = "kong.plugins.trust-sign.sign"

local function read_file(path)
  local file = assert(io.open(path, "rb"))
  local contents = assert(file:read("*a"))
  assert(file:close())
  return contents
end

local function value_matches_key(value, path, contents)
  if value == path or value == contents then
    return true
  end

  if type(value) == "table" or type(value) == "userdata" then
    for _, method_name in ipairs({ "to_PEM", "to_pem" }) do
      local method = value[method_name]
      if type(method) == "function" then
        for _, format in ipairs({ "private", "public" }) do
          local ok, pem = pcall(method, value, format)
          if ok and pem == contents then
            return true
          end
        end
      end
    end
  end

  return false
end

local function arguments_contain_key(arguments, path, contents)
  for _, value in ipairs(arguments) do
    if value_matches_key(value, path, contents) then
      return true
    end
  end
  return false
end

describe("token-exchange private key environment override", function()
  local original_getenv
  local captured_signer_arguments

  before_each(function()
    original_getenv = os.getenv
    os.getenv = function(name)
      if name == "KONG_SIGNING_CERT_KEY" then
        return ENV_KEY_PATH
      end
      return original_getenv(name)
    end

    captured_signer_arguments = nil
    local function record_signer_call(...)
      captured_signer_arguments = { ... }
      return string.rep("s", 64)
    end
    package.preload[SIGNER_MODULE] = function()
      return setmetatable({ sign = record_signer_call }, {
        __call = function(_, ...)
          return record_signer_call(...)
        end,
        __index = function()
          return record_signer_call
        end,
      })
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
  it("passes the KONG_SIGNING_CERT_KEY key to the assertion signer", function()
    local create_client_assertion = assert(require("client_assertion").create_client_assertion)
    local assertion = assert(create_client_assertion({
      private_key_location = CONFIG_KEY_PATH,
      client_id = "environment-override-client",
      token_endpoint = "https://tokens.example.test/exchange",
      algorithm = "RS256",
      expiration = 60,
    }))

    assert.matches("^[^.]+%.[^.]+%.[^.]+$", assertion)
    assert.is_table(captured_signer_arguments)

    local environment_key = read_file(ENV_KEY_PATH)
    local configured_key = read_file(CONFIG_KEY_PATH)
    assert.is_true(
      arguments_contain_key(captured_signer_arguments, ENV_KEY_PATH, environment_key)
    )
    assert.is_false(
      arguments_contain_key(captured_signer_arguments, CONFIG_KEY_PATH, configured_key)
    )
  end)
end)
