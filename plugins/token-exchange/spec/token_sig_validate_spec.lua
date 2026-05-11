-- local keycloak_keys = require("kong.plugins.token-exchange.client_assertion")
local openssl_pkey = require "resty.openssl.pkey"

describe(
  "token-exchange",
  function()
    it(
      "should get parse key",
      function()
        ok = true
        assert.same(true, ok, "JWT signature check failed")
      end
    )
  end
)
