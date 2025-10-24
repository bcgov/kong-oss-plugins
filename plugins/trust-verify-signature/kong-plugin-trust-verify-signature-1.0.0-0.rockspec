local plugin_name = "trust-verify-signature"
local package_name = "kong-plugin-"..plugin_name
local package_version = "1.0.0"
local rockspec_revision = "0"

package = package_name
version = package_version .. "-" .. rockspec_revision
supported_platforms = { "linux", "macosx" }

source = {
  url = "git://github.com/bcgov/kong-oss-plugins",
  tag = "v1.0.0",
  dir = "plugins/trust-verify-signature/src"
}

description = {
  summary = "Kong Gateway plugin used to verify a Signature using Signature Inputs",
  detailed = [[
      kong-plugin-trust-verify-signature is an Open Source plugin which verifies a Signature
  ]],
  homepage = "https://github.com/bcgov/kong-oss-plugins/plugins/trust-verify-signature",
  license = "Apache 2.0",
}

dependencies = {
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins."..plugin_name..".handler"] = "src/handler.lua",
    ["kong.plugins."..plugin_name..".schema"] = "src/schema.lua",
  }
}
