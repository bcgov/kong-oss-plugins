local plugin_name = "trust-sign"
local package_name = "kong-plugin-"..plugin_name
local package_version = "1.0.0"
local rockspec_revision = "0"

package = package_name
version = package_version .. "-" .. rockspec_revision
supported_platforms = { "linux", "macosx" }

source = {
  url = "git://github.com/bcgov/kong-oss-plugins",
  tag = "v1.0.0",
  dir = "plugins/trust-sign/src"
}

description = {
  summary = "Kong Gateway plugin used to prepare a signature base for signing and creates signature",
  detailed = [[
      kong-plugin-trust-sign is an Open Source plugin which prepares a signature base for signing and
      creates the signature, storing it in a response header or request header depending on the config.
  ]],
  homepage = "https://github.com/bcgov/kong-oss-plugins/plugins/trust-sign",
  license = "Apache 2.0",
}

dependencies = {
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins."..plugin_name..".digest"] = "src/digest.lua",
    ["kong.plugins."..plugin_name..".handler"] = "src/handler.lua",
    ["kong.plugins."..plugin_name..".schema"] = "src/schema.lua",
    ["kong.plugins."..plugin_name..".signature_base"] = "src/signature_base.lua",
  }
}
