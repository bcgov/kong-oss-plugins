local plugin_name = "trust-timestamp"
local package_name = "kong-plugin-"..plugin_name
local package_version = "1.0.0"
local rockspec_revision = "0"

package = package_name
version = package_version .. "-" .. rockspec_revision
supported_platforms = { "linux", "macosx" }

source = {
  url = "git://github.com/bcgov/kong-oss-plugins",
  tag = "v1.0.0",
  dir = "plugins/trust-timestamp/src"
}

description = {
  summary = "Kong Gateway plugin used to call a TS Authority to get an RFC-3161 timestamp document",
  detailed = [[
      kong-plugin-trust-timestamp is an Open Source plugin which sets a TS header with the timestamp document,
      from a timestamp authority
  ]],
  homepage = "https://github.com/bcgov/kong-oss-plugins/plugins/trust-timestamp",
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
