local plugin_name = "token-exchange"
local package_name = "kong-plugin-"..plugin_name
local package_version = "1.0.0"
local rockspec_revision = "0"

package = package_name
version = package_version .. "-" .. rockspec_revision
supported_platforms = { "linux", "macosx" }

source = {
  url = "git://github.com/bcgov/kong-oss-plugins",
  tag = "v1.0.0",
  dir = "plugins/token-exchange/src"
}

description = {
  summary = "Kong Gateway plugin used to exchange a token for another using a confidential client",
  detailed = [[
      kong-plugin-token-exchange is an Open Source plugin which calls a token endpoint to
      exchange for another token.
  ]],
  homepage = "https://github.com/bcgov/kong-oss-plugins/plugins/token-exchange",
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
