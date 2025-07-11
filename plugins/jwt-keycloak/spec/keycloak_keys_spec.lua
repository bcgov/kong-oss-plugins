local keycloak_keys = require("kong.plugins.jwt-keycloak.keycloak_keys")
local jwt_decoder = require "kong.plugins.jwt.jwt_parser"

describe(
  "keycloak_keys",
  function()
    it(
      "should get a public key ok",
      function()
        local keys,
          err =
          keycloak_keys.get_issuer_keys(
          "http://keycloak.localtest.me:9081/auth/realms/e2e/.well-known/openid-configuration"
        )
        if err then
          print("Error: " .. err)
        else
          print("Number of keys retrieved: " .. table.getn(keys))
        end
        assert.truthy("Yup.")
      end
    )
  end
)
