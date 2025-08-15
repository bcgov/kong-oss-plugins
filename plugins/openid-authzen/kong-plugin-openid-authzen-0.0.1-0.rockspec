local plugin_name = "openid-authzen"
local package_name = "kong-plugin-"..plugin_name
local package_version = "0.0.1"
local rockspec_revision = "0"

package = package_name
version = package_version .. "-" .. rockspec_revision
supported_platforms = { "linux", "macosx" }

source = {
  url = "git://github.com/bcgov/kong-oss-plugins",
  tag = "v1.0.0",
  dir = "plugins/mtls-auth/src"
}

description = {
  summary = "Kong Gateway plugin used to do a callout to a policy decision point",
  detailed = [[
      See https://openid.net/wg/authzen/specifications/
  ]],
  homepage = "https://github.com/bcgov/kong-oss-plugins/plugins/openid-authzen",
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
