local Schema = require "kong.db.schema"
local schema_def = require "schema"


local function config_schema()
  for _, field in ipairs(schema_def.fields) do
    if field.config then
      return assert(Schema.new(field.config))
    end
  end

  error("schema missing config field")
end


local function canonical_config(overrides)
  local config = {
    private_key_location = "/tmp/kong/fixtures/keys/rsa-2048.pem",
    client_id = "spec-client",
    token_endpoint = "https://issuer.example.test/token",
    algorithm = "RS256",
    expiration = 60,
    scopes = {},
    timeout = 10000,
  }

  for key, value in pairs(overrides or {}) do
    config[key] = value
  end

  return config
end


local function read_file(path)
  local file = assert(io.open(path, "rb"))
  local contents = assert(file:read("*a"))
  file:close()
  return contents
end


local function write_file(path, contents)
  local file = assert(io.open(path, "wb"))
  assert(file:write(contents))
  file:close()
end


local function decode_base64url(value)
  local normalized = value:gsub("-", "+"):gsub("_", "/")
  local remainder = #normalized % 4
  if remainder > 0 then
    normalized = normalized .. string.rep("=", 4 - remainder)
  end
  return assert(ngx.decode_base64(normalized))
end


local function signature_verifies(jwt, public_key_path)
  local header, payload, encoded_signature = assert(jwt:match("^([^.]+)%.([^.]+)%.([^.]+)$"))
  local input_path = os.tmpname()
  local signature_path = os.tmpname()
  write_file(input_path, header .. "." .. payload)
  write_file(signature_path, decode_base64url(encoded_signature))

  local first, _, third = os.execute(string.format(
    "openssl dgst -sha256 -verify %q -signature %q %q >/dev/null 2>&1",
    public_key_path,
    signature_path,
    input_path
  ))
  os.remove(input_path)
  os.remove(signature_path)

  return first == true or first == 0 or third == 0
end


local function with_token_exchange_stub(callback)
  local saved_http = package.loaded["resty.http"]
  local saved_assertion = package.loaded["client_assertion"]
  local saved_qualified_assertion = package.loaded["kong.plugins.token-exchange.client_assertion"]
  local saved_exchange = package.loaded["token_exchange"]
  local saved_kong = _G.kong
  local observed = { requests = 0 }

  _G.kong = {
    log = {
      debug = function() end,
      err = function() end,
    },
    request = {
      get_header = function(name)
        if name == "authorization" or name == "Authorization" then
          return "Bearer inbound-token"
        end
      end,
    },
  }

  package.loaded["resty.http"] = {
    new = function()
      return {
        set_timeout = function(_, timeout)
          observed.timeout = timeout
        end,
        request_uri = function(_, uri, options)
          observed.requests = observed.requests + 1
          observed.uri = uri
          observed.options = options
          return {
            status = 200,
            body = [[{"access_token":"exchanged-token"}]],
          }
        end,
      }
    end,
  }
  local assertion_stub = {
    create_client_assertion = function()
      return "stub-client-assertion"
    end,
  }
  package.loaded["client_assertion"] = assertion_stub
  package.loaded["kong.plugins.token-exchange.client_assertion"] = assertion_stub
  package.loaded["token_exchange"] = nil

  local ok, err = pcall(function()
    callback(assert(require("token_exchange").do_token_exchange), observed)
  end)

  package.loaded["resty.http"] = saved_http
  package.loaded["client_assertion"] = saved_assertion
  package.loaded["kong.plugins.token-exchange.client_assertion"] = saved_qualified_assertion
  package.loaded["token_exchange"] = saved_exchange
  _G.kong = saved_kong

  assert(ok, err)
end


describe("token-exchange configuration schema", function()
  local schema = config_schema()

  -- [Verifies: token-exchange.configuration-schema.required-fields]
  it("rejects each missing required field", function()
    for _, missing in ipairs({ "private_key_location", "client_id", "token_endpoint" }) do
      local config = canonical_config()
      config[missing] = nil
      local ok, err = schema:validate(config)
      assert.is_falsy(ok)
      assert.is_truthy(err[missing])
    end
  end)

  -- [Verifies: token-exchange.configuration-schema.enumerated-algorithms]
  it("rejects algorithms outside the configured enumeration", function()
    local ok, err = schema:validate(canonical_config({ algorithm = "HS256" }))
    assert.is_falsy(ok)
    assert.is_truthy(err.algorithm)
  end)

  -- [Verifies: token-exchange.configuration-schema.canonical-config-accepted]
  it("accepts a canonical config and supplies defaults", function()
    local config = {
      private_key_location = "/tmp/key.pem",
      client_id = "canonical-client",
      token_endpoint = "https://issuer.example.test/token",
    }
    local ok, err = schema:validate(config)
    assert.is_truthy(ok, tostring(err))

    local processed, process_err = schema:process_auto_fields(config, "insert")
    assert.is_truthy(processed, tostring(process_err))
    assert.equals("RS256", processed.algorithm)
    assert.equals(60, processed.expiration)
    assert.same({}, processed.scopes)
    assert.equals(10000, processed.timeout)
  end)

  -- [Verifies: token-exchange.configuration-schema.nonpositive-expiration-accepted]
  it("rejects zero and negative expiration", function()
    for _, expiration in ipairs({ 0, -1 }) do
      local ok, err = schema:validate(canonical_config({ expiration = expiration }))
      assert.is_falsy(ok)
      assert.is_truthy(err.expiration)
    end
  end)
end)


describe("token-exchange request seam", function()
  -- [Verifies: token-exchange.token-endpoint-request.standard-request]
  it("constructs the standard verified form request", function()
    with_token_exchange_stub(function(do_token_exchange, observed)
      local result, err = do_token_exchange(canonical_config(), "inbound-token")
      assert.is_truthy(result, tostring(err))
      assert.equals(1, observed.requests)
      assert.equals("https://issuer.example.test/token", observed.uri)
      assert.equals(10000, observed.timeout)
      assert.equals("POST", observed.options.method)
      assert.is_true(observed.options.ssl_verify)
      assert.equals("application/json", observed.options.headers.Accept)
      assert.equals("application/x-www-form-urlencoded", observed.options.headers["Content-Type"])

      local form = ngx.decode_args(observed.options.body)
      assert.equals("spec-client", form.client_id)
      assert.equals("stub-client-assertion", form.client_assertion)
      assert.equals("urn:ietf:params:oauth:client-assertion-type:jwt-bearer", form.client_assertion_type)
      assert.equals("urn:ietf:params:oauth:grant-type:token-exchange", form.grant_type)
      assert.equals("urn:ietf:params:oauth:token-type:access_token", form.subject_token_type)
      assert.equals("urn:ietf:params:oauth:token-type:access_token", form.requested_token_type)
      assert.equals("inbound-token", form.subject_token)
    end)
  end)

  -- [Verifies: token-exchange.token-endpoint-request.timeout-field-unavailable]
  it("accepts and uses a configured timeout and defaults an omitted timeout", function()
    local schema = config_schema()
    local configured = canonical_config({ timeout = 4321 })
    local configured_ok, configured_err = schema:validate(configured)
    assert.is_truthy(configured_ok, tostring(configured_err))
    local processed_configured = assert(schema:process_auto_fields(configured, "insert"))
    assert.equals(4321, processed_configured.timeout)

    local omitted = canonical_config()
    omitted.timeout = nil
    local omitted_ok, omitted_err = schema:validate(omitted)
    assert.is_truthy(omitted_ok, tostring(omitted_err))
    local processed_omitted = assert(schema:process_auto_fields(omitted, "insert"))
    assert.equals(10000, processed_omitted.timeout)

    for _, case in ipairs({
      { config = configured, expected = 4321 },
      { config = omitted, expected = 10000 },
    }) do
      with_token_exchange_stub(function(do_token_exchange, observed)
        local result, err = do_token_exchange(case.config, "token")
        assert.is_truthy(result, tostring(err))
        assert.equals(case.expected, observed.timeout)
      end)
    end
  end)
end)


describe("token-exchange private key resolution seam", function()
  -- [Verifies: token-exchange.private-key-resolution.environment-override-ignored]
  it("signs with KONG_SIGNING_CERT_KEY instead of private_key_location", function()
    local environment_key = "../../testsuite/local/kong/fixtures/keys/rsa-3072.pem"
    local environment_public_key = "../../testsuite/local/kong/fixtures/keys/rsa-3072.pub.pem"
    local configured_key = "../../testsuite/local/kong/fixtures/keys/rsa-2048.pem"
    local configured_public_key = "../../testsuite/local/kong/fixtures/keys/rsa-2048.pub.pem"
    local sign_module_name = "kong.plugins.trust-sign.sign"
    local saved_getenv = os.getenv
    local saved_kong = _G.kong
    local saved_client_assertion = package.loaded["client_assertion"]
    local saved_qualified_client_assertion = package.loaded["kong.plugins.token-exchange.client_assertion"]
    local saved_sign_module = package.loaded[sign_module_name]
    local saved_sign_preload = package.preload[sign_module_name]
    local resolver_calls = 0
    local resolved_key_path

    os.getenv = function(name)
      if name == "KONG_SIGNING_CERT_KEY" then
        return environment_key
      end
      return saved_getenv(name)
    end
    _G.kong = {
      log = {
        debug = function() end,
        err = function() end,
      },
    }
    package.loaded["client_assertion"] = nil
    package.loaded["kong.plugins.token-exchange.client_assertion"] = nil
    package.loaded[sign_module_name] = nil
    package.preload[sign_module_name] = function()
      local function load_key(...)
        local path
        for index = 1, select("#", ...) do
          local value = select(index, ...)
          if value == resolved_key_path then
            path = value
            break
          end
        end
        return read_file(assert(path, "environment-resolved key path was not passed to key loader"))
      end

      return {
        get_private_key_location = function(config)
          resolver_calls = resolver_calls + 1
          resolved_key_path = os.getenv("KONG_SIGNING_CERT_KEY") or config.private_key_location
          return resolved_key_path
        end,
        get_kong_key = load_key,
        get_private_key = load_key,
      }
    end

    local ok, assertion_or_error = pcall(function()
      local create_client_assertion = assert(require("client_assertion").create_client_assertion)
      return assert(create_client_assertion(canonical_config({
        private_key_location = configured_key,
      })))
    end)

    os.getenv = saved_getenv
    _G.kong = saved_kong
    package.loaded["client_assertion"] = saved_client_assertion
    package.loaded["kong.plugins.token-exchange.client_assertion"] = saved_qualified_client_assertion
    package.loaded[sign_module_name] = saved_sign_module
    package.preload[sign_module_name] = saved_sign_preload

    assert(ok, assertion_or_error)
    assert.equals(1, resolver_calls)
    assert.equals(environment_key, resolved_key_path)
    assert.is_true(signature_verifies(assertion_or_error, environment_public_key))
    assert.is_false(signature_verifies(assertion_or_error, configured_public_key))
  end)
end)
