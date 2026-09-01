local plugin_name = "dpop"
local package_name = "kong-plugin-"..plugin_name
local package_version = "1.0.0"
local rockspec_revision = "0"

package = package_name
version = package_version .. "-" .. rockspec_revision
supported_platforms = { "linux", "macosx" }

source = {
  url = "git://github.com/bcgov/kong-oss-plugins",
  tag = "v1.0.0",
  dir = "plugins/dpop/src"
}

description = {
  summary = "Kong Gateway plugin used to validate a DPoP token",
  detailed = [[
      kong-plugin-dpop is an Open Source plugin which takes a DPoP access token and a DPoP proof,
      and validates that it is valid.
  ]],
  homepage = "https://github.com/bcgov/kong-oss-plugins/plugins/dpop",
  license = "Apache 2.0",
}

dependencies = {
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins."..plugin_name..".handler"] = "src/handler.lua",
    ["kong.plugins."..plugin_name..".schema"] = "src/schema.lua",
    ["kong.plugins."..plugin_name..".filter"] = "src/filter.lua",
  }
}
