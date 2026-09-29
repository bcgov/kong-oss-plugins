local HANDLER_MODULE = "kong.plugins.token-exchange.handler"
local EXCHANGE_MODULE = "kong.plugins.token-exchange.token_exchange"
local LOG_MODULE = "kong.plugins.plugin-log.log"
local META_MODULE = "kong.meta"
local REQUEST_ID_MODULE = "kong.observability.tracing.request_id"

describe("token-exchange scope and audience transfer", function()
  local original_kong
  local original_modules = {}
  local exchange
  local exchange_call
  local exit_call
  local error_logs
  local request_headers
  local handler

  local function remember_module(name)
    original_modules[name] = {value = package.loaded[name]}
  end

  before_each(function()
    original_kong = _G.kong
    exchange_call = nil
    exit_call = nil
    error_logs = {}
    request_headers = {}

    for _, name in ipairs({
      HANDLER_MODULE,
      EXCHANGE_MODULE,
      LOG_MODULE,
      META_MODULE,
      REQUEST_ID_MODULE,
    }) do
      remember_module(name)
    end

    exchange = {
      do_token_exchange = function(conf, scopes, audiences)
        exchange_call = {conf = conf, scopes = scopes, audiences = audiences}
        return {access_token = "exchanged-token"}
      end
    }
    package.loaded[HANDLER_MODULE] = nil
    package.loaded[EXCHANGE_MODULE] = exchange
    package.loaded[LOG_MODULE] = {
      continue_with_reason = function() end,
      exit_with_reason = function(reason, status, body, headers)
        exit_call = {
          reason = reason,
          status = status,
          body = body,
          headers = headers
        }
        return exit_call
      end
    }
    package.loaded[META_MODULE] = {version = "test"}
    package.loaded[REQUEST_ID_MODULE] = {get = function() return "request-id-123" end}

    _G.kong = {
      ctx = {
        shared = {
          jwt_keycloak_token = {
            claims = {
              scope = "openid records.read records.write records.read",
              aud = {"requesting-client", "sdx-client", "provider-api", "requesting-client"}
            }
          }
        }
      },
      log = {
        warn = function() end,
        err = function(...)
          local values = {}
          for i = 1, select("#", ...) do
            values[i] = tostring(select(i, ...))
          end
          table.insert(error_logs, table.concat(values))
        end
      },
      service = {
        request = {
          set_header = function(name, value)
            request_headers[name] = value
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

  -- [Verifies: token-exchange.scope-transfer.verified-subject-scopes]
  -- [Verifies: token-exchange.audience-transfer.configured-and-original]
  it("passes verified scopes and normalized audiences to the exchange", function()
    handler:access({client_id = "sdx-client", audience = "provider-api"})

    assert.same({"openid", "records.read", "records.write"}, exchange_call.scopes)
    assert.same({"provider-api", "requesting-client"}, exchange_call.audiences)
    assert.equals("provider-api", exchange_call.conf.audience)
    assert.equals("Bearer exchanged-token", request_headers.Authorization)
    assert.is_nil(exit_call)
  end)

  -- [Verifies: token-exchange.audience-transfer.string-audience]
  -- [Verifies: token-exchange.audience-transfer.configured-audience-required]
  it("accepts a string SDX audience and still requests the configured audience", function()
    _G.kong.ctx.shared.jwt_keycloak_token.claims.aud = "sdx-client"

    handler:access({client_id = "sdx-client", audience = "provider-api"})

    assert.same({"provider-api"}, exchange_call.audiences)
    assert.is_nil(exit_call)
  end)

  -- [Verifies: token-exchange.audience-transfer.subject-not-authorized]
  it("returns a correlated, redacted 400 when the subject audience does not authorize SDX", function()
    _G.kong.ctx.shared.jwt_keycloak_token.claims.aud = {"requesting-client", "optional-provider"}

    handler:access({client_id = "sdx-client", audience = "provider-api"})

    assert.is_nil(exchange_call)
    assert.equals(400, exit_call.status)
    assert.equals("SDX_TOKEN_EXCHANGE_NOT_AUTHORIZED", exit_call.body.error.code)
    assert.equals(
      "The supplied token is not authorized for SDX token exchange. " ..
        "Refer to the SDX documentation and use request ID request-id-123 when requesting support.",
      exit_call.body.message
    )
    assert.equals("request-id-123", exit_call.headers["X-Kong-Request-Id"])
    assert.equals("request-id-123", exit_call.reason.detail.request_id)
    assert.same({"requesting-client", "optional-provider"}, exit_call.reason.detail.original_audiences)

    local public_response = require("cjson.safe").encode(exit_call.body)
    assert.is_nil(public_response:find("requesting%-client"))
    assert.is_nil(public_response:find("optional%-provider"))
    assert.is_nil(public_response:find("sdx%-client"))

    local diagnostic_log = table.concat(error_logs, "\n")
    assert.is_truthy(diagnostic_log:find("request%-id%-123"))
    assert.is_truthy(diagnostic_log:find("requesting%-client"))
    assert.is_truthy(diagnostic_log:find("optional%-provider"))
    assert.is_truthy(diagnostic_log:find("sdx%-client"))
  end)

  -- [Verifies: token-exchange.audience-transfer.malformed-subject-audience]
  it("returns the same authorization error for malformed subject audiences", function()
    for _, audience in ipairs({false, {}, {"sdx-client", false}, ""}) do
      exchange_call = nil
      exit_call = nil
      if audience == false then
        _G.kong.ctx.shared.jwt_keycloak_token.claims.aud = nil
      else
        _G.kong.ctx.shared.jwt_keycloak_token.claims.aud = audience
      end

      handler:access({client_id = "sdx-client", audience = "provider-api"})

      assert.is_nil(exchange_call)
      assert.equals(400, exit_call.status)
      assert.equals("SDX_TOKEN_EXCHANGE_NOT_AUTHORIZED", exit_call.body.error.code)
    end
  end)

  -- [Verifies: token-exchange.audience-transfer.invalid-configured-audience]
  it("returns a configuration error for a missing or self-targeted configured audience", function()
    for _, audience in ipairs({false, "", "sdx-client"}) do
      exchange_call = nil
      exit_call = nil
      local conf = {client_id = "sdx-client"}
      if audience ~= false then
        conf.audience = audience
      end

      handler:access(conf)

      assert.is_nil(exchange_call)
      assert.equals(500, exit_call.status)
      assert.equals("SDX_TOKEN_EXCHANGE_CONFIGURATION_ERROR", exit_call.body.error.code)
      assert.equals("request-id-123", exit_call.headers["X-Kong-Request-Id"])
    end
  end)

  -- [Verifies: token-exchange.scope-transfer.invalid-subject-scope]
  it("rejects a missing, non-string, or empty subject scope before exchange", function()
    for _, value in ipairs({false, {}, "   "}) do
      exchange_call = nil
      exit_call = nil
      if value == false then
        _G.kong.ctx.shared.jwt_keycloak_token.claims.scope = nil
      else
        _G.kong.ctx.shared.jwt_keycloak_token.claims.scope = value
      end

      handler:access({})

      assert.is_nil(exchange_call)
      assert.equals(400, exit_call.status)
      assert.equals("Token exchange failed", exit_call.body.message)
      assert.equals("E4", exit_call.body.error.code)
    end
  end)

  -- [Verifies: token-exchange.configuration-error.invalid-scope]
  it("maps IdP invalid_scope to a correlated, redacted configuration error", function()
    exchange.do_token_exchange = function(conf, scopes, audiences)
      exchange_call = {conf = conf, scopes = scopes, audiences = audiences}
      return nil,
        {code = "E2"},
        nil,
        {
          idp_status = 400,
          idp_response = {
            error = "invalid_scope",
            error_description = "client is missing records.write"
          }
        }
    end

    handler:access({client_id = "sdx-client", audience = "provider-api"})

    assert.equals(500, exit_call.status)
    assert.equals("SDX_TOKEN_EXCHANGE_CONFIGURATION_ERROR", exit_call.body.error.code)
    assert.equals(
      "The SDX token-exchange client is not configured to complete this request. " ..
        "Refer to the SDX Kong token-exchange plugin logs using request ID request-id-123 for details.",
      exit_call.body.message
    )
    assert.equals("request-id-123", exit_call.headers["X-Kong-Request-Id"])
    assert.same({"openid", "records.read", "records.write"}, exit_call.reason.detail.requested_scopes)
    assert.equals("provider-api", exit_call.reason.detail.configured_audience)
    assert.same({"provider-api", "requesting-client"}, exit_call.reason.detail.requested_audiences)
    assert.equals(400, exit_call.reason.detail.idp_status)
    assert.equals("invalid_scope", exit_call.reason.detail.idp_error)
    assert.is_nil(exit_call.reason.detail.idp_response)

    local public_response = require("cjson.safe").encode(exit_call.body)
    assert.is_nil(public_response:find("records", 1, true))
    assert.is_nil(public_response:find("provider-api", 1, true))
    assert.is_nil(public_response:find("error_description", 1, true))

    local diagnostic_log = table.concat(error_logs, "\n")
    assert.is_truthy(diagnostic_log:find("request%-id%-123"))
    assert.is_truthy(diagnostic_log:find("records.read", 1, true))
    assert.is_truthy(diagnostic_log:find("provider%-api"))
    assert.is_nil(diagnostic_log:find("client is missing", 1, true))
  end)

  -- [Verifies: token-exchange.configuration-error.non-scope-errors-unchanged]
  it("keeps other token endpoint errors on the existing response path", function()
    exchange.do_token_exchange = function()
      return nil,
        {code = "E2"},
        nil,
        {idp_status = 401, idp_response = {error = "invalid_client"}}
    end

    handler:access({client_id = "sdx-client", audience = "provider-api"})

    assert.equals(400, exit_call.status)
    assert.equals("Token exchange failed", exit_call.body.message)
    assert.equals("E2", exit_call.body.error.code)
  end)

  -- [Verifies: token-exchange.configuration-error.invalid-target]
  it("maps IdP invalid_target to the correlated configuration error", function()
    exchange.do_token_exchange = function()
      return nil,
        {code = "E2"},
        nil,
        {idp_status = 400, idp_response = {error = "invalid_target"}}
    end

    handler:access({client_id = "sdx-client", audience = "provider-api"})

    assert.equals(500, exit_call.status)
    assert.equals("SDX_TOKEN_EXCHANGE_CONFIGURATION_ERROR", exit_call.body.error.code)
    assert.equals("invalid_target", exit_call.reason.detail.idp_error)
  end)
end)
