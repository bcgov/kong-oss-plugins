local plugin_name = "trust-registry-ai"
local package_name = "kong-plugin-" .. plugin_name
local package_version = "1.0.0"
local rockspec_revision = "0"

package = package_name
version = package_version .. "-" .. rockspec_revision
supported_platforms = { "linux", "macosx" }

source = {
  url = "git://github.com/bcgov/kong-oss-plugins",
  tag = "v1.0.0",
  dir = "plugins/trust-registry-ai/src"
}

description = {
  summary = "Kong Gateway plugin that serves registered public keys as a JWKS endpoint.",
  detailed = [[
      kong-plugin-trust-registry-ai is an Open Source plugin that exposes Kong's
      registered public keys in JSON Web Key Set (JWKS) format per RFC 7517.
      Supports retrieval of all keys or filtering by named key set.
  ]],
  homepage = "https://github.com/bcgov/kong-oss-plugins/plugins/trust-registry-ai",
  license = "Apache 2.0",
}

dependencies = {}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins." .. plugin_name .. ".handler"]    = "src/handler.lua",
    ["kong.plugins." .. plugin_name .. ".schema"]     = "src/schema.lua",
    ["kong.plugins." .. plugin_name .. ".pem_to_jwk"] = "src/pem_to_jwk.lua",
  }
}
