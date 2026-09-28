local HANDLER_MODULE = "kong.plugins.token-exchange.handler"
local EXCHANGE_MODULE = "kong.plugins.token-exchange.token_exchange"
local LOG_MODULE = "kong.plugins.plugin-log.log"
local META_MODULE = "kong.meta"
local HTTP_MODULE = "resty.http"

describe("token-exchange provider headers", function()
  local original_kong
  local original_modules = {}
  local headers
  local handler

  local function remember_module(name)
    original_modules[name] = {value = package.loaded[name]}
  end

  before_each(function()
    original_kong = _G.kong
    headers = {
      ["X-SDX-Original-AZP"] = "caller-supplied"
    }
    remember_module(HANDLER_MODULE)
    remember_module(EXCHANGE_MODULE)
    remember_module(LOG_MODULE)
    remember_module(META_MODULE)
    remember_module(HTTP_MODULE)

    package.loaded[HANDLER_MODULE] = nil
    package.loaded[EXCHANGE_MODULE] = {
      do_token_exchange = function()
        return {access_token = "exchanged-token"}
      end
    }
    package.loaded[LOG_MODULE] = {
      continue_with_reason = function() end,
      exit_with_reason = function(...)
        return ...
      end
    }
    package.loaded[META_MODULE] = {version = "test"}
    package.loaded[HTTP_MODULE] = {}

    _G.kong = {
      ctx = {shared = {}},
      log = {
        warn = function() end,
        err = function() end
      },
      service = {
        request = {
          clear_header = function(name)
            headers[name] = nil
          end,
          set_header = function(name, value)
            headers[name] = value
          end
        }
      }
    }

    handler = assert(require(HANDLER_MODULE))
  end)

  after_each(function()
    _G.kong = original_kong
    for name, saved in pairs(original_modules) do
      package.loaded[name] = saved.value
    end
    original_modules = {}
  end)

  -- [Verifies: token-exchange.original-azp-header.verified-azp-forwarded]
  it("overwrites the original AZP header from the verified subject token", function()
    _G.kong.ctx.shared.jwt_keycloak_token = {
      claims = {azp = "original-requesting-client"}
    }

    handler:access({})

    assert.equals("Bearer exchanged-token", headers.Authorization)
    assert.equals("original-requesting-client", headers["X-SDX-Original-AZP"])
  end)

  -- [Verifies: token-exchange.original-azp-header.unverified-value-removed]
  it("removes a caller-supplied AZP header when no verified token is available", function()
    handler:access({})

    assert.equals("Bearer exchanged-token", headers.Authorization)
    assert.is_nil(headers["X-SDX-Original-AZP"])
  end)

  -- [Verifies: token-exchange.original-azp-header.invalid-azp-omitted]
  it("omits an empty AZP claim", function()
    _G.kong.ctx.shared.jwt_keycloak_token = {claims = {azp = ""}}

    handler:access({})

    assert.is_nil(headers["X-SDX-Original-AZP"])
  end)
end)
