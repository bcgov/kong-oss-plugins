local ngx = ngx
local openssl_pkey = require("resty.openssl.pkey")
local hello = require("kong.plugins.trust-hello.hello")
local cjson = require "cjson"
local kong_meta = require "kong.meta"
local encode_base64 = ngx.encode_base64
local kong = kong

local TrustHelloHandler = {
  PRIORITY = 940,
  VERSION = kong_meta.version
}

function TrustHelloHandler:access(conf)
  kong.log.warn("TrustHelloHandler:access called")
end

function TrustHelloHandler:header_filter(conf)
  kong.log.warn("TrustHelloHandler:header_filter called")

  -- local server_cert = kong.tls.get_request_ssl_pointer()

  -- local server_cert = ngx.var.kong_upstream_ssl_server_raw_cert

  -- kong.log.warn("Server Cert", server_cert)
end

function TrustHelloHandler:certificate(conf)
  kong.log.warn("TrustHelloHandler:certificate called")

  local response = hello.collect_data()

  kong.log.warn(cjson.encode(response))

  -- Return JSON response
  return kong.response.exit(
    200,
    response,
    {
      ["Content-Type"] = "application/json"
    }
  )
end

return TrustHelloHandler
