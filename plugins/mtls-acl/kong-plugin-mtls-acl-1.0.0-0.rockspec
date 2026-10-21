local plugin_name = "mtls-acl"
local package_name = "kong-plugin-"..plugin_name
local package_version = "1.0.0"
local rockspec_revision = "0"

package = package_name
version = package_version .. "-" .. rockspec_revision
supported_platforms = { "linux", "macosx" }

source = {
  url = "git://github.com/bcgov/kong-oss-plugins",
  tag = "v1.0.0",
  dir = "plugins/mtls-acl/src"
}

description = {
  summary = "Kong Gateway plugin used to restrict access based on information provided in an HTTP header",
  detailed = [[
      kong-plugin-mtls-acl is an Open Source plugin which restricts access based on certificate information
	  provided in an HTTP header. It is similar (but simpler) than the acl built-in plugin.

      This plugin requires the mtls-auth plugin to have been already enabled on the Service or Route.
  ]],
  homepage = "https://github.com/bcgov/kong-oss-plugins/plugins/mtls-acl",
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
