local os = require "os"
local io = require "io"
local ssl = require("ngx.ssl")

local http = require "resty.http"
local cjson = require "cjson.safe"

local httpc = http.new()
local req_body = kong.request.get_raw_body()

local client_cert_path = os.getenv("KONG_CLIENT_SSL_CERT")
local client_key_path = os.getenv("KONG_CLIENT_SSL_CERT_KEY")

if req_body then
  -- Process the raw body string
  kong.log.info("Request body: ", req_body)
end

local function read_file(filename)
  local file = io.open(filename, "r")
  if not file then
    kong.log.err("Error: Could not open file " .. filename)
    return kong.response.exit(500, "Error: Could not open file " .. filename)
  end

  local content = file:read("*all") -- Read entire file
  file:close()
  return content
end

local config = {
  -- Server details
  host = "sdx-authz-apps-gov-bc-ca-lab.apps.gov.bc.ca",
  port = 443,
  path = "/auth/realms/sdx/protocol/openid-connect/token",
  -- Client certificate files
  cert_file = assert(ssl.parse_pem_cert(read_file(client_cert_path))),
  key_file = assert(ssl.parse_pem_priv_key(read_file(client_key_path))),
  -- Request data
  post_data = req_body,
  content_type = "application/x-www-form-urlencoded"
}

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
      ["Content-Type"] = config.content_type,
      ["Accept"] = "application/json",
      ["DPoP"] = kong.request.get_header("DPoP")
    },
    body = config.post_data,
    ssl_verify = true,
    ssl_client_cert = config.cert_file,
    ssl_client_priv_key = config.key_file
  }
)

if not res then
  return kong.response.exit(502, "Upstream request failed: " .. (err or "unknown error"))
end

kong.response.set_header("Content-Type", res.headers["Content-Type"] or "application/json")
return kong.response.exit(res.status, res.body)
