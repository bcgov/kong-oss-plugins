local plugin_name = "trust-registry"
local package_name = "kong-plugin-"..plugin_name
local package_version = "1.0.0"
local rockspec_revision = "0"

package = package_name
version = package_version .. "-" .. rockspec_revision
supported_platforms = { "linux", "macosx" }

source = {
  url = "git://github.com/bcgov/kong-oss-plugins",
  tag = "v1.0.0",
  dir = "plugins/trust-registry/src"
}

description = {
  summary = "Kong Gateway plugin used to output a JWKS from the keys setup in Kong",
  detailed = [[
      kong-plugin-trust-registry is an Open Source plugin which returns a list of keys in JWKS format.
  ]],
  homepage = "https://github.com/bcgov/kong-oss-plugins/plugins/trust-registry",
  license = "Apache 2.0",
}

dependencies = {
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins."..plugin_name..".handler"] = "src/handler.lua",
    ["kong.plugins."..plugin_name..".schema"] = "src/schema.lua",
    ["kong.plugins."..plugin_name..".pem_to_jwks"] = "src/pem_to_jwks.lua",
  }
}
