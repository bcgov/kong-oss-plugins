local MODULE = "kong.plugins.token-exchange.token_exchange"
local ASSERTION_MODULE = "kong.plugins.token-exchange.client_assertion"
local HTTP_MODULE = "resty.http"
local META_MODULE = "kong.meta"

describe("token-exchange scopes", function()
  local original_kong
  local original_modules = {}
  local response
  local captured_request
  local warnings
  local exchange
  local authorization_header

  local function remember_module(name)
    original_modules[name] = {value = package.loaded[name]}
  end

  before_each(function()
    original_kong = _G.kong
    response = {
      status = 200,
      body = '{"access_token":"exchanged-token"}'
    }
    captured_request = nil
    warnings = {}
    authorization_header = "Bearer subject-token"

    for _, name in ipairs({MODULE, ASSERTION_MODULE, HTTP_MODULE, META_MODULE}) do
      remember_module(name)
    end
    package.loaded[MODULE] = nil
    package.loaded[ASSERTION_MODULE] = {
      create_client_assertion = function()
        return "client-assertion"
      end
    }
    package.loaded[HTTP_MODULE] = {
      new = function()
        return {
          set_timeout = function() end,
          request_uri = function(_, uri, options)
            captured_request = {uri = uri, options = options}
            return response
          end
        }
      end
    }
    package.loaded[META_MODULE] = {version = "test"}

    _G.kong = {
      request = {
        get_header = function(name)
          assert.equals("Authorization", name)
          return authorization_header
        end
      },
      log = {
        err = function() end,
        warn = function(...)
          local values = {}
          for i = 1, select("#", ...) do
            values[i] = tostring(select(i, ...))
          end
          table.insert(warnings, table.concat(values))
        end
      }
    }

    exchange = assert(require(MODULE))
  end)

  after_each(function()
    _G.kong = original_kong
    for name, saved in pairs(original_modules) do
      package.loaded[name] = saved.value
    end
    original_modules = {}
  end)

  local function config()
    return {
      client_id = "sdx-client",
      client_assertion_type = "ignored",
      token_endpoint = "https://tokens.example.test/exchange",
      scopes = {"configured.scope.must.not.be.used"}
    }
  end

  it("parses and deduplicates scopes through the shared helper", function()
    assert.same(
      {"openid", "records.read", "records.write"},
      exchange.unique_scopes("  openid records.read records.write records.read  ")
    )
    assert.same({}, exchange.unique_scopes("   "))
    assert.is_nil(exchange.unique_scopes(nil))
  end)

  it("rejects a missing or non-bearer Authorization header without calling the endpoint", function()
    for _, authorization in ipairs({false, "Basic credentials", "bearer lowercase"}) do
      authorization_header = authorization == false and nil or authorization
      captured_request = nil

      local token, err, status = exchange.do_token_exchange(config(), {"openid"})

      assert.is_nil(token)
      assert.same({code = "E4"}, err)
      assert.equals(401, status)
      assert.is_nil(captured_request)
    end
  end)

  -- [Verifies: token-exchange.scope-transfer.exchange-request]
  it("sends scopes supplied from the verified subject token", function()
    local token, err = exchange.do_token_exchange(
      config(),
      {"openid", "records.read", "records.write"}
    )

    assert.is_nil(err)
    assert.equals("exchanged-token", token.access_token)
    assert.matches("scope=openid%+records%.read%+records%.write", captured_request.options.body)
    assert.is_nil(captured_request.options.body:find("configured.scope", 1, true))
  end)

  -- [Verifies: token-exchange.scope-transfer.omitted-response-scope]
  it("accepts an omitted response scope as identical to the request", function()
    local token, err = exchange.do_token_exchange(config(), {"openid", "records.read"})

    assert.is_nil(err)
    assert.equals("exchanged-token", token.access_token)
    assert.same({}, warnings)
  end)

  -- [Verifies: token-exchange.scope-transfer.response-scope-order]
  it("does not warn when the declared granted scope set only changes order", function()
    response.body = '{"access_token":"exchanged-token","scope":"records.read openid"}'

    local token, err = exchange.do_token_exchange(config(), {"openid", "records.read"})

    assert.is_nil(err)
    assert.equals("exchanged-token", token.access_token)
    assert.same({}, warnings)
  end)

  -- [Verifies: token-exchange.scope-transfer.response-scope-mismatch]
  it("warns and continues when declared granted scopes differ", function()
    response.body = '{"access_token":"exchanged-token","scope":"openid provider.default"}'

    local token, err = exchange.do_token_exchange(config(), {"openid", "records.read"})

    assert.is_nil(err)
    assert.equals("exchanged-token", token.access_token)
    assert.equals(1, #warnings)
    assert.is_truthy(warnings[1]:find("granted scopes differ", 1, true))
    assert.is_truthy(warnings[1]:find("records.read", 1, true))
    assert.is_truthy(warnings[1]:find("provider.default", 1, true))
  end)
end)
