local plugin_name = "trust-kms"
local package_name = "kong-plugin-"..plugin_name
local package_version = "1.0.0"
local rockspec_revision = "0"

package = package_name
version = package_version .. "-" .. rockspec_revision
supported_platforms = { "linux", "macosx" }

source = {
  url = "git://github.com/bcgov/kong-oss-plugins",
  tag = "v1.0.0",
  dir = "plugins/trust-hello/src"
}

description = {
  summary = "Kong Gateway plugin used to perform various KMS functions.",
  detailed = [[
      kong-plugin-trust-hello is an Open Source plugin that provides key management functions
  ]],
  homepage = "https://github.com/bcgov/kong-oss-plugins/plugins/trust-hello",
  license = "Apache 2.0",
}

dependencies = {
  "lua-resty-aws"
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins."..plugin_name..".handler"] = "src/handler.lua",
    ["kong.plugins."..plugin_name..".schema"] = "src/schema.lua",
    ["kong.plugins."..plugin_name..".backends.aws"] = "src/backends/aws.lua",
    ["kong.plugins."..plugin_name..".backends.local"] = "src/backends/local.lua",
    ["kong.plugins."..plugin_name..".csr"] = "src/csr.lua",
  }
}
