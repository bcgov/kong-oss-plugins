local plugin_name = "trust-registry-ai-openspec"
local package_name = "kong-plugin-" .. plugin_name
local package_version = "1.0.0"
local rockspec_revision = "0"

package = package_name
version = package_version .. "-" .. rockspec_revision
supported_platforms = { "linux", "macosx" }

source = {
  url = "git://github.com/bcgov/kong-oss-plugins",
  tag = "v1.0.0",
  dir = "plugins/trust-registry-ai-openspec/src"
}

description = {
  summary = "Kong Gateway plugin that exposes Kong keys and keysets as a JWKS endpoint.",
  detailed = [[
      kong-plugin-trust-registry-ai-openspec serves public keys from Kong's
      keys and key_sets entities as a RFC 7517 JWKS document, enabling
      SDX Edge Server hosts to publish their public keys for JWS verification.
  ]],
  homepage = "https://github.com/bcgov/kong-oss-plugins/plugins/trust-registry-ai-openspec",
  license = "Apache 2.0",
}

dependencies = {}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins." .. plugin_name .. ".handler"] = "src/handler.lua",
    ["kong.plugins." .. plugin_name .. ".schema"]  = "src/schema.lua",
    ["kong.plugins." .. plugin_name .. ".jwks"]    = "src/jwks.lua",
  }
}
