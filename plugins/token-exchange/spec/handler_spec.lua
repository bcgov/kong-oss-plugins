local HANDLER_MODULE = "kong.plugins.token-exchange.handler"
local EXCHANGE_MODULE = "kong.plugins.token-exchange.token_exchange"
local LOG_MODULE = "kong.plugins.plugin-log.log"
local META_MODULE = "kong.meta"
local HTTP_MODULE = "resty.http"
local REQUEST_ID_MODULE = "kong.observability.tracing.request_id"

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
      claims = {
        azp = "original-requesting-client",
        aud = {"sdx-client"}
      }
    }

    handler:access({client_id = "sdx-client", audience = "provider-api"})

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
    _G.kong.ctx.shared.jwt_keycloak_token = {
      claims = {
        azp = "",
        aud = {"sdx-client"}
      }
    }

    handler:access({client_id = "sdx-client", audience = "provider-api"})

    assert.is_nil(headers["X-SDX-Original-AZP"])
  end)
end)

describe("token-exchange scope and audience transfer", function()
  local original_kong
  local original_modules = {}
  local exchange
  local exchange_call
  local exit_call
  local error_logs
  local info_logs
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
    info_logs = {}
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
      end,
      unique_scopes = function(scope_string)
        if type(scope_string) ~= "string" then
          return nil
        end
        local scopes = {}
        local seen = {}
        for scope in scope_string:gmatch("%S+") do
          if not seen[scope] then
            table.insert(scopes, scope)
            seen[scope] = true
          end
        end
        return scopes
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
              aud = {"requesting-client", "sdx-client", "provider-api", "sdx-client", "requesting-client"}
            }
          }
        }
      },
      log = {
        warn = function() end,
        info = function(...)
          local values = {}
          for i = 1, select("#", ...) do
            values[i] = tostring(select(i, ...))
          end
          table.insert(info_logs, table.concat(values))
        end,
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
          clear_header = function(name)
            request_headers[name] = nil
          end,
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
  -- [Verifies: token-exchange.audience-transfer.exchange-client-retained]
  it("filters verified scopes, appends the target scope, and normalizes audiences", function()
    handler:access({
      client_id = "sdx-client",
      audience = "provider-api",
      scopes = {"records.read", "records.write"},
      scope_source = "verified_subject_token",
      target_privacy_zone_scope = "urn:ca:bc:gov:provider"
    })

    assert.same({
      "records.read",
      "records.write",
      "urn:ca:bc:gov:provider"
    }, exchange_call.scopes)
    local scope_filter_log = table.concat(info_logs, "\n")
    assert.is_truthy(scope_filter_log:find("records.read", 1, true))
    assert.is_truthy(scope_filter_log:find("records.write", 1, true))
    assert.is_truthy(scope_filter_log:find("openid", 1, true))
    assert.same({"provider-api", "requesting-client", "sdx-client"}, exchange_call.audiences)
    assert.equals("provider-api", exchange_call.conf.audience)
    assert.equals("Bearer exchanged-token", request_headers.Authorization)
    assert.is_nil(exit_call)
  end)

  it("deduplicates the target privacy-zone scope already present in the subject token", function()
    _G.kong.ctx.shared.jwt_keycloak_token.claims.scope =
      "openid urn:ca:bc:gov:provider records.read urn:ca:bc:gov:provider"

    handler:access({
      client_id = "sdx-client",
      scopes = {"records.read", "records.write"},
      scope_source = "verified_subject_token",
      target_privacy_zone_scope = "urn:ca:bc:gov:provider"
    })

    assert.same({
      "urn:ca:bc:gov:provider",
      "records.read"
    }, exchange_call.scopes)
    assert.is_nil(exit_call)
  end)

  it("uses configured scopes only when that source is explicit", function()
    _G.kong.ctx.shared.jwt_keycloak_token = nil

    handler:access({
      scopes = {"configured.read"},
      scope_source = "configured",
      target_privacy_zone_scope = "must.not.be.composed"
    })

    assert.same({"configured.read"}, exchange_call.scopes)
    assert.is_nil(exit_call)
  end)

  -- [Verifies: token-exchange.audience-transfer.string-audience]
  -- [Verifies: token-exchange.audience-transfer.configured-audience-optional]
  it("accepts a string SDX audience without a configured provider audience", function()
    _G.kong.ctx.shared.jwt_keycloak_token.claims.aud = "sdx-client"

    handler:access({
      client_id = "sdx-client",
      scopes = {"records.read", "records.write"},
      scope_source = "verified_subject_token"
    })

    assert.same({"sdx-client"}, exchange_call.audiences)
    assert.is_nil(exit_call)
  end)

  -- [Verifies: token-exchange.audience-transfer.subject-not-authorized]
  it("returns a correlated, redacted 400 when the subject audience does not authorize SDX", function()
    _G.kong.ctx.shared.jwt_keycloak_token.claims.aud = {"requesting-client", "optional-provider"}

    handler:access({
      client_id = "sdx-client",
      audience = "provider-api",
      scopes = {"records.read", "records.write"},
      scope_source = "verified_subject_token"
    })

    assert.is_nil(exchange_call)
    assert.equals(400, exit_call.status)
    assert.equals("SDX_TOKEN_EXCHANGE_NOT_AUTHORIZED", exit_call.body.error.code)
    assert.equals(
      "The supplied token is not authorized for SDX token exchange. " ..
        "Refer to the SDX documentation and use request ID request-id-123 when requesting support.",
      exit_call.body.message
    )
    assert.is_nil(exit_call.headers)
    assert.is_nil(exit_call.reason.detail.request_id)
    assert.same({"requesting-client", "optional-provider"}, exit_call.reason.detail.original_audiences)

    local public_response = require("cjson.safe").encode(exit_call.body)
    assert.is_nil(public_response:find("requesting%-client"))
    assert.is_nil(public_response:find("optional%-provider"))
    assert.is_nil(public_response:find("sdx%-client"))

    local diagnostic_log = table.concat(error_logs, "\n")
    assert.is_nil(diagnostic_log:find("request%-id%-123"))
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

      handler:access({
        client_id = "sdx-client",
        audience = "provider-api",
        scopes = {"records.read", "records.write"},
        scope_source = "verified_subject_token"
      })

      assert.is_nil(exchange_call)
      assert.equals(400, exit_call.status)
      assert.equals("SDX_TOKEN_EXCHANGE_NOT_AUTHORIZED", exit_call.body.error.code)
    end
  end)

  -- [Verifies: token-exchange.audience-transfer.configured-audience-optional]
  it("ignores an empty audience and deduplicates a self-targeted audience", function()
    _G.kong.ctx.shared.jwt_keycloak_token.claims.aud = {"sdx-client"}
    for _, audience in ipairs({false, "", "sdx-client"}) do
      exchange_call = nil
      exit_call = nil
      local conf = {
        client_id = "sdx-client",
        scopes = {"records.read", "records.write"},
        scope_source = "verified_subject_token"
      }
      if audience ~= false then
        conf.audience = audience
      end

      handler:access(conf)

      assert.same({"sdx-client"}, exchange_call.audiences)
      assert.is_nil(exit_call)
    end
  end)

  -- [Verifies: token-exchange.scope-transfer.managed-allowlist-required]
  it("fails closed when the SDX-managed scope allowlist is missing or empty", function()
    for _, scopes in ipairs({false, {}}) do
      exchange_call = nil
      exit_call = nil
      local conf = {
        client_id = "sdx-client",
        scope_source = "verified_subject_token"
      }
      if scopes ~= false then
        conf.scopes = scopes
      end

      handler:access(conf)

      assert.is_nil(exchange_call)
      assert.equals(500, exit_call.status)
      assert.equals("SDX_TOKEN_EXCHANGE_CONFIGURATION_ERROR", exit_call.body.error.code)
      assert.equals(
        "SDX-managed application scope allowlist is missing or empty",
        exit_call.reason.detail.configuration_reason
      )
    end
  end)

  -- [Verifies: token-exchange.scope-transfer.invalid-subject-scope]
  it("fails closed when verified token context is unavailable", function()
    _G.kong.ctx.shared.jwt_keycloak_token = nil

    handler:access({
      scopes = {"records.read", "records.write"},
      scope_source = "verified_subject_token"
    })

    assert.is_nil(exchange_call)
    assert.equals(500, exit_call.status)
    assert.equals("E4", exit_call.body.error.code)
  end)

  it("rejects a missing, non-string, or empty verified subject scope before exchange", function()
    for _, value in ipairs({false, {}, "   "}) do
      exchange_call = nil
      exit_call = nil
      if value == false then
        _G.kong.ctx.shared.jwt_keycloak_token.claims.scope = nil
      else
        _G.kong.ctx.shared.jwt_keycloak_token.claims.scope = value
      end

      handler:access({
        scopes = {"records.read", "records.write"},
        scope_source = "verified_subject_token"
      })

      assert.is_nil(exchange_call)
      assert.equals(500, exit_call.status)
      assert.equals("Token exchange failed", exit_call.body.message)
      assert.equals("E4", exit_call.body.error.code)
    end
  end)

  it("fails closed when a configured target privacy-zone scope is malformed", function()
    handler:access({
      scopes = {"records.read", "records.write"},
      scope_source = "verified_subject_token",
      target_privacy_zone_scope = "scope.one scope.two"
    })

    assert.is_nil(exchange_call)
    assert.equals(500, exit_call.status)
    assert.equals("SDX_TOKEN_EXCHANGE_CONFIGURATION_ERROR", exit_call.body.error.code)
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

    handler:access({
      client_id = "sdx-client",
      audience = "provider-api",
      scopes = {"records.read", "records.write"},
      scope_source = "verified_subject_token"
    })

    assert.equals(500, exit_call.status)
    assert.equals("SDX_TOKEN_EXCHANGE_CONFIGURATION_ERROR", exit_call.body.error.code)
    assert.equals(
      "The SDX token-exchange client is not configured to complete this request. " ..
        "Refer to the SDX Kong token-exchange plugin logs using request ID request-id-123 for details.",
      exit_call.body.message
    )
    assert.is_nil(exit_call.headers)
    assert.same({"records.read", "records.write"}, exit_call.reason.detail.requested_scopes)
    assert.equals("provider-api", exit_call.reason.detail.configured_audience)
    assert.same({"provider-api", "requesting-client", "sdx-client"}, exit_call.reason.detail.requested_audiences)
    assert.equals(400, exit_call.reason.detail.idp_status)
    assert.equals("invalid_scope", exit_call.reason.detail.idp_error)
    assert.is_nil(exit_call.reason.detail.request_id)
    assert.is_nil(exit_call.reason.detail.idp_response)

    local public_response = require("cjson.safe").encode(exit_call.body)
    assert.is_nil(public_response:find("records", 1, true))
    assert.is_nil(public_response:find("provider-api", 1, true))
    assert.is_nil(public_response:find("error_description", 1, true))

    local diagnostic_log = table.concat(error_logs, "\n")
    assert.is_nil(diagnostic_log:find("request%-id%-123"))
    assert.is_truthy(diagnostic_log:find("records.read", 1, true))
    assert.is_truthy(diagnostic_log:find("provider%-api"))
    assert.is_nil(diagnostic_log:find("client is missing", 1, true))
  end)

  -- [Verifies: token-exchange.configuration-error.non-configuration-errors-unchanged]
  it("keeps unrelated token endpoint errors on the existing response path", function()
    exchange.do_token_exchange = function()
      return nil,
        {code = "E2"},
        nil,
        {
          idp_status = 400,
          idp_response = {error = "invalid_request", error_description = "Invalid token"}
        }
    end

    handler:access({
      client_id = "sdx-client",
      audience = "provider-api",
      scopes = {"records.read", "records.write"},
      scope_source = "verified_subject_token"
    })

    assert.equals(500, exit_call.status)
    assert.equals("Token exchange failed", exit_call.body.message)
    assert.equals("E2", exit_call.body.error.code)
  end)

  -- [Verifies: token-exchange.configuration-error.invalid-audience]
  it("maps IdP audience configuration errors to the correlated configuration error", function()
    for _, idp_response in ipairs({
      {error = "invalid_target"},
      {error = "invalid_client", error_description = "Audience not found"},
      {error = "invalid_request", error_description = "Requested audience not available: provider-api"}
    }) do
      exit_call = nil
      exchange.do_token_exchange = function()
        return nil, {code = "E2"}, nil, {idp_status = 400, idp_response = idp_response}
      end

      handler:access({
        client_id = "sdx-client",
        audience = "provider-api",
        scopes = {"records.read", "records.write"},
        scope_source = "verified_subject_token"
      })

      assert.equals(500, exit_call.status)
      assert.equals("SDX_TOKEN_EXCHANGE_CONFIGURATION_ERROR", exit_call.body.error.code)
      assert.equals(idp_response.error, exit_call.reason.detail.idp_error)
    end
  end)
end)
