local plugin_name = "plugin-log"
local package_name = "kong-plugin-"..plugin_name
local package_version = "1.0.0"
local rockspec_revision = "0"

package = package_name
version = package_version .. "-" .. rockspec_revision
supported_platforms = { "linux", "macosx" }

source = {
  url = "git://github.com/bcgov/kong-oss-plugins",
  tag = "v1.0.0",
  dir = "plugins/plugin-log/src"
}

description = {
  summary = "Shared functions for the plugins in this repository.",
  detailed = [[
      kong-bcgov-share provides a few shared functions used by all plugins.
  ]],
  homepage = "https://github.com/bcgov/kong-oss-plugins/plugins/plugin-log",
  license = "Apache 2.0",
}

dependencies = {
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins."..plugin_name..".log"] = "src/log.lua",
    ["kong.plugins."..plugin_name..".schema"] = "src/schema.lua",
    ["kong.plugins."..plugin_name..".handler"] = "src/handler.lua",
  }
}
