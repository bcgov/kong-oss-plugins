-- Run from the repository root:
-- resty testsuite/unit/trust-kms-missing-public-key.lua
-- Exercise the real counter-sign handler and public-key verification guards.
local root = "plugins/"
local function module(name, path)
  package.loaded[name] = assert(loadfile(root .. path))()
  return package.loaded[name]
end
local function stub(name, value)
  package.loaded[name] = value or {}
end
local noop = function() end
local key, cert, key_error, cert_error
local headers, response, cache_calls, parse_calls
_G.ngx = { encode_base64 = noop, decode_base64 = noop, log = noop, ERR = "error" }
_G.kong = {
  log = { warn = noop, err = noop },
  cache = { get = function()
    cache_calls = cache_calls + 1
    return key, key_error
  end },
  ctx = { shared = {} },
  request = { get_header = function() return "header.payload.signature" end },
  service = { request = { set_header = function(k, v) headers[k] = v end } },
  response = {
    get_source = function() return "service" end,
    get_header = function() return "header.payload.signature" end,
    set_header = function(k, v) headers[k] = v end,
    exit = function(status, body) response = { status = status, body = body } end,
  },
}
local getenv = os.getenv
os.getenv = function(name)
  if name == "KONG_SIGNING_CERT" then return nil end
  return getenv(name)
end
stub("pl.file")
stub("resty.openssl.x509", { new = function()
  parse_calls = parse_calls + 1
  return cert, cert_error
end })
stub("resty.openssl.digest", { new = function() return { update = function() return true end } end })
stub("resty.openssl.pkey")
stub("resty.openssl")
stub("kong.plugins.trust-kms.backends.aws")
stub("kong.plugins.trust-kms.backends.local")
stub("kong.plugins.trust-kms.csr")
stub("cjson")
stub("kong.meta", { version = "test" })
stub("ngx.base64", { encode_base64url = function(s) return s end })
stub("kong.plugins.jwt.jwt_parser")
stub("kong.plugins.trust-sign.digest")
stub("kong.plugins.trust-sign.sign")
stub("kong.observability.tracing.request_id", { get = noop })
module("kong.plugins.plugin-log.log", "plugin-log/src/log.lua")
local filter = module("kong.plugins.trust-sign.signature_base", "trust-sign/src/signature_base.lua")
os.getenv = getenv
filter.sign = function() return "signed" end
local handler = module("kong.plugins.trust-kms.handler", "trust-kms/src/handler.lua")
local cases = {
  { name = "unconfigured", location = nil, expected = "Public key location is not configured", reads = 0, parses = 0 },
  { name = "empty location", location = "", expected = "Public key location is not configured", reads = 0, parses = 0 },
  { name = "missing file", location = "missing.pem", key_error = "not found", expected = "Public key not found", reads = 1, parses = 0 },
  { name = "empty file", location = "empty.pem", key = "", expected = "Public key not found", reads = 1, parses = 0 },
  { name = "malformed certificate", location = "bad.pem", key = "bad", cert_error = "invalid PEM", expected = "Failed to load public key certificate: invalid PEM", reads = 1, parses = 1 },
  { name = "no certificate public key", location = "no-key.pem", key = "cert", cert = { get_pubkey = function() return nil, "no key" end }, expected = "Failed to create public key object: no key", reads = 1, parses = 1 },
  { name = "valid certificate", location = "valid.pem", key = "cert", cert = { get_pubkey = function() return { verify = function() return true end } end }, reads = 1, parses = 1 },
}
for _, direction in ipairs({ "request", "response" }) do
  for _, case in ipairs(cases) do
    key, key_error, cert, cert_error = case.key, case.key_error, case.cert, case.cert_error
    headers, response, cache_calls, parse_calls = {}, nil, 0, 0
    kong.ctx.shared = {}
    local conf = { operation = "sign", backend = "local", direction = direction, signature_header_key = "X-Edge-Token", public_key_location = case.location }
    if direction == "request" then handler:access(conf) else handler:header_filter(conf) end
    if case.expected then
      assert(response and response.status == 500, case.name .. ": expected HTTP 500")
      assert(response.body.message == "Failed to counter-sign: Failed to verify signature: " .. case.expected, case.name .. ": wrong error message")
      assert(headers["X-Entity-Sig"] == nil, case.name .. ": must not forward a signature")
      assert(kong.ctx.shared.plugin_results[1].continued == false)
    else
      assert(response == nil and headers["X-Entity-Sig"] == "signed", "valid certificate must still sign")
    end
    assert(cache_calls == case.reads and parse_calls == case.parses, case.name .. ": unexpected key access")
    print("PASS " .. direction .. ": " .. case.name)
  end
end
