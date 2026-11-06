-- Run from repository root using LuaJIT; all external dependencies are stubbed.
local source, observed, verified, marker
local headers = {}
_G.kong = {
  response = {
    get_source = function() return source end,
    get_header = function(name) observed = true; return headers[name] end,
    set_header = function() marker = true end,
  },
  log = { warn = function() end },
}
package.loaded['kong.meta'] = { version = 'test' }
package.loaded['kong.plugins.jwt.jwt_parser'] = {
  new = function(_, token)
    if token == 'bad' then return nil, 'invalid JWT' end
    return { claims = {} }
  end,
}
package.loaded['kong.plugins.trust-verify-signature.signature'] = {
  verify_jwt_signature = function() verified = true; return true end,
}
package.loaded['kong.plugins.plugin-log.log'] = {
  exit_with_reason = function(_, status, body) return { status = status, message = body.message } end,
  continue_with_reason = function() end,
}
local handler = dofile('plugins/trust-verify-signature/src/handler.lua')
local conf = { direction = 'response', signature_header_key = 'X-Edge-Token', manifest_type = 'signature-only' }
for _, origin in ipairs({ 'exit', 'error' }) do
  source, observed, verified, marker = origin, false, false, false
  local result = handler:header_filter(conf)
  assert(result == nil and not observed and not verified and not marker, 'must preserve original local rejection/error')
end
source = 'service'
local missing = handler:header_filter(conf)
assert(missing.status == 401 and missing.message == 'Missing Signature in X-Edge-Token', 'unsigned provider response must fail')
headers['X-Edge-Token'] = 'bad'
local invalid = handler:header_filter(conf)
assert(invalid.status == 401, 'malformed provider signature must fail')
headers['X-Edge-Token'] = 'valid'
handler:header_filter(conf)
assert(verified and marker, 'signed provider response must still be verified')
print('PASS: local exit, gateway error, unsigned provider, malformed signature, valid signature')
