local os = require "os"
local io = require "io"
local ssl = require("ngx.ssl")

local http = require "resty.http"
local cjson = require "cjson.safe"

local httpc = http.new()

local client_cert_path = os.getenv("KONG_CLIENT_SSL_CERT")
local client_key_path = os.getenv("KONG_CLIENT_SSL_CERT_KEY")

local function urlencode(str)
  if not str then
    return ""
  end
  str = tostring(str)
  str =
    string.gsub(
    str,
    "([^%w%.%- ])",
    function(c)
      return string.format("%%%02X", string.byte(c))
    end
  )
  str = string.gsub(str, " ", "+")
  return str
end

local function read_file(filename)
  local file = io.open(filename, "r")
  if not file then
    kong.log.err("Error: Could not open file " .. filename)
    return kong.response.exit(500, "Error: Could not open file " .. filename)
  end

  local content = file:read("*all")
  file:close()
  return content
end

local config = {
  host = "sdx-authz-apps-gov-bc-ca-lab.apps.gov.bc.ca",
  port = 443,
  path = "/auth/realms/sdx/protocol/openid-connect/token/introspect",
  cert_file = assert(ssl.parse_pem_cert(read_file(client_cert_path))),
  key_file = assert(ssl.parse_pem_priv_key(read_file(client_key_path))),
  client_id = "gw-introspection"
}

local data = {
  client_id = config.client_id,
  token = kong.request.get_header("Authorization"):match("Bearer%s+(.+)"),
  token_type_hint = "access_token"
}

local encoded_body = ""
local first = true
for key, value in pairs(data) do
  if not first then
    encoded_body = encoded_body .. "&"
  end
  encoded_body = encoded_body .. urlencode(key) .. "=" .. urlencode(value)
  first = false
end

if not config.cert_file or not config.key_file then
  kong.log.err("Failed to load certificates as cdata")
  return kong.response.exit(500, "Failed to load certificates as cdata")
end

local res,
  err =
  httpc:request_uri(
  "https://" .. config.host .. ":" .. config.port .. config.path,
  {
    method = "POST",
    headers = {
      ["Content-Type"] = "application/x-www-form-urlencoded",
      ["Accept"] = "application/jwt"
    },
    body = encoded_body,
    ssl_verify = true,
    ssl_client_cert = config.cert_file,
    ssl_client_priv_key = config.key_file
  }
)

if not res then
  return kong.response.exit(502, "Introspection failed: " .. (err or "unknown error"))
end

if res.status ~= 200 then
  return kong.response.exit(401, "Introspection failed: " .. (res.body or "unknown error"))
end

kong.service.request.set_header("X-INTROSPECTION", res.body)
kong.service.request.set_header("X-INBOUND-TOKEN", kong.request.get_header("Authorization"))

res.body = cjson.decode(res.body)
if not res.body then
  return kong.response.exit(502, "Introspection failed: Could not decode response.")
end

if res.body.jwt == nil then
  return kong.response.exit(401, "Introspection failed: Expecting jwt in response.")
end

kong.service.request.set_header("Authorization", "Bearer " .. res.body.jwt)
