local plugin_name = "trust-ledger"
local package_name = "kong-plugin-"..plugin_name
local package_version = "1.0.0"
local rockspec_revision = "0"

package = package_name
version = package_version .. "-" .. rockspec_revision
supported_platforms = { "linux", "macosx" }

source = {
  url = "git://github.com/bcgov/kong-oss-plugins",
  tag = "v1.0.0",
  dir = "plugins/trust-ledger/src"
}

description = {
  summary = "Kong Gateway plugin used to upload an artifact to an immutable ledger",
  detailed = [[
      kong-plugin-trust-ledger is an Open Source plugin which takes an RFC-3161 timestamp document,
      and registers it on an immutable ledger.
  ]],
  homepage = "https://github.com/bcgov/kong-oss-plugins/plugins/trust-ledger",
  license = "Apache 2.0",
}

dependencies = {
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins."..plugin_name..".handler"] = "src/handler.lua",
    ["kong.plugins."..plugin_name..".schema"] = "src/schema.lua",
    ["kong.plugins."..plugin_name..".ledgers.rekor"] = "src/ledgers/rekor.lua",
  }
}
