-- Run from the repository root: resty testsuite/unit/trust-kms-missing-public-key.lua
-- Real OpenSSL keys and signatures; stub only Kong DAOs, cache and request/response APIs.
local root = "plugins/"
local function module(name, path)
  package.loaded[name] = assert(loadfile(root .. path))()
  return package.loaded[name]
end
local function stub(name, value) package.loaded[name] = value or {} end
local noop = function() end
local pkey = require "resty.openssl.pkey"
local signer = assert(pkey.new({ type = "RSA", bits = 2048 }))
local other = assert(pkey.new({ type = "RSA", bits = 2048 }))
local private = assert(signer:to_PEM("private"))
local public = assert(signer:to_PEM("public"))
local wrong_public = assert(other:to_PEM("public"))
local keys, keyset, dao_error, key_bytes, headers, response, sign_calls, reads, in_response
local aws_body, aws_status, aws_sign_calls, aws_sign_key
local algorithm = "RSASSA_PSS_SHA_256"
local arn = "arn:aws:kms:ca-central-1:123456789012:key/signing-key"
local getenv = os.getenv
os.getenv = function(name)
  if name == "KONG_SIGNING_CERT_KEY" then return "/mounted/signing.key" end
  if name == "KONG_SIGNING_CERT" then return nil end
  return getenv(name)
end
_G.kong = {
  log = { warn = noop, err = noop },
  cache = { get = function(_, name, opts, loader, ...)
    assert(not in_response, "response must reuse the key validated in access")
    return loader(...)
  end },
  db = {
    key_sets = { select_by_name = function() return keyset, dao_error end },
    keys = { page_for_set = function(_, _, _, offset)
      -- Force pagination to exercise a match on a later page.
      if not offset then return {}, nil, nil, "next" end
      return keys
    end },
  },
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
stub("pl.file", { read = function(path)
  assert(path == "/mounted/signing.key", "environment must take precedence")
  reads = reads + 1
  return key_bytes, "not found"
end })
stub("kong.tools.utils")
stub("resty.openssl")
stub("ltn12")
stub("resty.aws.config", { global = {} })
stub("resty.aws", function()
  return { KMS = function() return {
    getPublicKey = function()
      assert(not in_response, "AWS public-key lookup must run in access")
      return { status = aws_status, body = aws_body }
    end,
    sign = function(_, request)
      aws_sign_calls = aws_sign_calls + 1
      assert(request.KeyId == arn, "must sign with resolved ARN, not configured alias")
      return { status = 200, body = { Signature = "aws-signed", KeyId = aws_sign_key or arn } }
    end,
  } end }
end)

stub("kong.plugins.trust-kms.csr")
stub("kong.meta", { version = "test" })
stub("kong.plugins.jwt.jwt_parser")
stub("kong.plugins.trust-sign.digest")
stub("kong.observability.tracing.request_id", { get = noop })
module("kong.plugins.plugin-log.log", "plugin-log/src/log.lua")
module("kong.plugins.trust-sign.sign", "trust-sign/src/sign.lua")
local filter = module("kong.plugins.trust-sign.signature_base", "trust-sign/src/signature_base.lua")
os.getenv = getenv
local real_sign = filter.sign
filter.sign = function(conf, input, hash, pem)
  sign_calls = sign_calls + 1
  assert(pem == private, "must sign with the bytes matched against the keyset")
  return real_sign(conf, input, hash, pem)
end
module("kong.plugins.trust-kms.backends.aws", "trust-kms/src/backends/aws.lua")
module("kong.plugins.trust-kms.backends.local", "trust-kms/src/backends/local.lua")
local handler = module("kong.plugins.trust-kms.handler", "trust-kms/src/handler.lua")
local registered = { kid = "registered", pem = { public_key = public } }
local cases = {
  { name = "missing keyset config", no_config = true, expected = "keyset_name is required" },
  { name = "keyset not found", no_set = true, expected = "key set not found" },
  { name = "DAO failure", dao_error = "database unavailable", expected = "database unavailable" },
  { name = "empty keyset", keys = {}, expected = "no keyset entry matches" },
  { name = "unrelated public key", keys = {{ kid = "wrong", pem = { public_key = wrong_public } }}, expected = "no keyset entry matches" },
  { name = "missing kid", keys = {{ pem = { public_key = public } }}, expected = "no keyset entry matches" },
  { name = "ambiguous registration", keys = {registered, registered}, expected = "multiple keyset entries match" },
  { name = "unreadable private key", missing_key = true, expected = "Unable to load private key" },
  { name = "malformed private key", bad_key = true, expected = "Unable to parse private key" },
  { name = "registered PEM", keys = {registered} },
  { name = "registered JWK", keys = {{ kid = "jwk", jwk = assert(signer:tostring("public", "JWK")) }} },
  { name = "AWS registered PEM", backend = "aws", keys = {registered} },
  { name = "AWS registered JWK", backend = "aws", keys = {{ kid = "jwk", jwk = assert(signer:tostring("public", "JWK")) }} },
  { name = "AWS unregistered", backend = "aws", expected = "no keyset entry matches" },
  { name = "AWS ambiguous", backend = "aws", keys = {registered, registered}, expected = "multiple keyset entries match" },
  { name = "AWS missing config", backend = "aws", no_config = true, expected = "keyset_name is required" },
  { name = "AWS lookup fails", backend = "aws", aws_status = 403, expected = "Failed to get public key" },
  { name = "AWS wrong usage", backend = "aws", usage = "ENCRYPT_DECRYPT", expected = "not a signing key" },
  { name = "AWS wrong algorithm", backend = "aws", algorithms = {}, expected = "does not support" },
  { name = "AWS malformed DER", backend = "aws", public_key = ngx.encode_base64("bad DER"), expected = "Invalid AWS public key" },
  { name = "AWS wrong signing key", backend = "aws", keys = {registered}, wrong_sign_key = true, signed_failure = true, expected = "AWS signing key does not match" },
}
for _, direction in ipairs({ "request", "response" }) do
  for _, case in ipairs(cases) do
    keys, keyset, dao_error = case.keys or {}, { id = "set-id" }, case.dao_error
    if case.no_set then keyset = nil end
    aws_body = { PublicKey = case.public_key or ngx.encode_base64(assert(signer:tostring("public", "DER"))),
      KeyId = arn, KeyUsage = case.usage or "SIGN_VERIFY", SigningAlgorithms = case.algorithms or {algorithm} }
    aws_status, aws_sign_calls, aws_sign_key = case.aws_status or 200, 0, nil
    if case.wrong_sign_key then aws_sign_key = "different-arn" end
    key_bytes = private
    if case.missing_key then key_bytes = nil elseif case.bad_key then key_bytes = "bad PEM" end
    headers, response, sign_calls, reads, in_response = {}, nil, 0, 0, false
    kong.ctx.shared = {}
    kong.ctx.plugin = {}
    local conf = { operation = "sign", backend = case.backend or "local", direction = direction,
      signature_header_key = "X-Edge-Token", keyset_name = "entity-keys", private_key_location = "/ignored.key", key_id = "alias/signing", signature_algorithm = algorithm }
    if case.no_config then conf.keyset_name = nil end
    handler:access(conf)
    if direction == "response" and not response then
      in_response = true
      handler:response(conf)
    end
    if case.expected then
      assert(response and response.status == 500, case.name .. ": expected HTTP 500")
      assert(response.body.message:find(case.expected, 1, true), case.name .. ": " .. response.body.message)
      assert(headers["X-Entity-Sig"] == nil and sign_calls == 0, case.name .. ": must not forward a signature")
      assert(aws_sign_calls == (case.signed_failure and 1 or 0), case.name .. ": unexpected AWS signing")
      assert(kong.ctx.shared.plugin_results[1].continued == false)
    elseif case.backend == "aws" then
      assert(headers["X-Entity-Sig"] == "aws-signed" and reads == 0 and sign_calls == 0 and aws_sign_calls == 1)
    else
      assert(response == nil and sign_calls == 1 and reads == 1, case.name .. ": must load the signing key once")
      local digest = assert(require("resty.openssl.digest").new("sha256"))
      assert(digest:update("signature"))
      local bytes = assert(require("ngx.base64").decode_base64url(headers["X-Entity-Sig"]))
      assert(signer:verify(bytes, digest), "counter-signature must verify with the registered key")
    end
    print("PASS " .. direction .. ": " .. case.name)
  end
end

-- Preserve trust-sign's existing API while routing it through the public resolver.
in_response = false
key_bytes, keyset, keys, dao_error = private, {id = "set-id"}, {registered}, nil
local signing = package.loaded["kong.plugins.trust-sign.sign"]
assert(signing.resolve_kid({keyset_name = "entity-keys"}) == "registered")
assert(signing.resolve_public_kid({keyset_name = "entity-keys"}, public) == "registered")
local kid, err = signing.resolve_public_kid({keyset_name = "entity-keys"}, nil)
assert(kid == nil and err == "signing public key is required")
print("PASS shared resolver and trust-sign compatibility")
