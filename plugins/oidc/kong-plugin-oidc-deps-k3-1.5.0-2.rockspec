package = "kong-plugin-oidc-deps-k3"
version = "1.5.0-2"
source = {
  url = "git://github.com/bcgov/kong-oss-plugins",
  tag = "main",
  dir = "plugins/oidc"
}

dependencies = {
  "lua-resty-openidc ~> 1.8.0-1"
}

build = {
  type = "builtin",
  modules = {
  }
}
