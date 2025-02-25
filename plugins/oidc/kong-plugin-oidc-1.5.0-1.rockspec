package = "kong-plugin-oidc"
version = "1.5.0-1"
source = {
  url = "git://github.com/bcgov/kong-oss-plugins",
  tag = "main",
  dir = "plugins/oidc"
}

description = {
  summary = "A Kong plugin for implementing the OpenID Connect Relying Party (RP) functionality",
  detailed = [[
    kong-oidc is a Kong plugin for implementing the OpenID Connect Relying Party.

    When used as an OpenID Connect Relying Party it authenticates users against an OpenID Connect Provider using OpenID Connect Discovery and the Basic Client Profile (i.e. the Authorization Code flow).

    It maintains sessions for authenticated users by leveraging lua-resty-session thus offering a configurable choice between storing the session state in a client-side browser cookie or use in of the server-side storage mechanisms shared-memory|memcache|redis.

    It supports server-wide caching of resolved Discovery documents and validated Access Tokens.

    It can be used as a reverse proxy terminating OAuth/OpenID Connect in front of an origin server so that the origin server/services can be protected with the relevant standards without implementing those on the server itself.
  ]],
  homepage = "https://github.com/bcgov/kong-oss-plugins",
  license = "Apache 2.0"
}

dependencies = {
  "lua-resty-openidc ~> 1.7.6-3"
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.oidc.filter"] = "src/filter.lua",
    ["kong.plugins.oidc.handler"] = "src/handler.lua",
    ["kong.plugins.oidc.schema"] = "src/schema.lua",
    ["kong.plugins.oidc.session"] = "src/session.lua",
    ["kong.plugins.oidc.utils"] = "src/utils.lua"
  }
}
