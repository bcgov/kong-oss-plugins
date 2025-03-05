package = "kong-plugin-oidc-deps-k2"
version = "1.5.0-2"
source = {
  url = "git://github.com/bcgov/kong-oss-plugins",
  tag = "main",
  dir = "plugins/oidc"
}

dependencies = {
  "lua-resty-openidc ~> 1.7.6-3"
}

build = {
  type = "builtin",
  modules = {
  }
}
