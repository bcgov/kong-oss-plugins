local plugin_name = "trust-verify-digest"
local package_name = "kong-plugin-"..plugin_name
local package_version = "1.0.0"
local rockspec_revision = "0"

package = package_name
version = package_version .. "-" .. rockspec_revision
supported_platforms = { "linux", "macosx" }

source = {
  url = "git://github.com/bcgov/kong-oss-plugins",
  tag = "v1.0.0",
  dir = "plugins/trust-verify-digest/src"
}

description = {
  summary = "Kong Gateway plugin used to verify a Content-Digest against the contents",
  detailed = [[
      kong-plugin-trust-verify-digest is an Open Source plugin which verifies a content digest
  ]],
  homepage = "https://github.com/bcgov/kong-oss-plugins/plugins/trust-verify-digest",
  license = "Apache 2.0",
}

dependencies = {
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins."..plugin_name..".handler"] = "src/handler.lua",
    ["kong.plugins."..plugin_name..".schema"] = "src/schema.lua",
    ["kong.plugins."..plugin_name..".digest"] = "src/digest.lua",
  }
}
