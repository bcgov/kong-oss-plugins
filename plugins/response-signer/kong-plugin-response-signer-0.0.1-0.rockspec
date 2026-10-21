local plugin_name = "response-signer"
local package_name = "kong-plugin-"..plugin_name
local package_version = "0.0.1"
local rockspec_revision = "0"

package = package_name
version = package_version .. "-" .. rockspec_revision
supported_platforms = { "linux", "macosx" }

source = {
  url = "git://github.com/bcgov/kong-oss-plugins",
  tag = "v1.0.0",
  dir = "plugins/response-signer/src"
}

description = {
  summary = "Kong Gateway plugin used to sign a response document",
  detailed = [[
  ]],
  homepage = "https://github.com/bcgov/kong-oss-plugins/plugins/response-signer",
  license = "Apache 2.0",
}

dependencies = {
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins."..plugin_name..".body_transformer"] = "src/body_transformer.lua",
    ["kong.plugins."..plugin_name..".handler"] = "src/handler.lua",
    ["kong.plugins."..plugin_name..".header_transformer"] = "src/header_transformer.lua",
    ["kong.plugins."..plugin_name..".schema"] = "src/schema.lua",
    ["kong.plugins."..plugin_name..".sign"] = "src/sign.lua",
  }
}
