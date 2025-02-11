package = "kong-plugin-jwt-keycloak"
version = "1.5.0-1"
source = {
  url = "git://github.com/bcgov/kong-oss-plugins",
  tag = "main",
  dir = "plugins/jwt-keycloak"
}

description = {
  summary = "A Kong plugin that will validate tokens issued by keycloak",
  homepage = "https://github.com/bcgov/kong-oss-plugins",
  license = "Apache 2.0"
}

dependencies = {
  "lua ~> 5"
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.jwt-keycloak.handler"]            = "src/handler.lua",
    ["kong.plugins.jwt-keycloak.schema"]             = "src/schema.lua",
    ["kong.plugins.jwt-keycloak.keycloak_keys"]      = "src/keycloak_keys.lua",
    ["kong.plugins.jwt-keycloak.key_conversion"]     = "src/key_conversion.lua",
    ["kong.plugins.jwt-keycloak.validators.audience"] = "src/validators/audience.lua",
    ["kong.plugins.jwt-keycloak.validators.issuers"] = "src/validators/issuers.lua",
    ["kong.plugins.jwt-keycloak.validators.roles"]   = "src/validators/roles.lua",
    ["kong.plugins.jwt-keycloak.validators.scope"]   = "src/validators/scope.lua",
  }
}
