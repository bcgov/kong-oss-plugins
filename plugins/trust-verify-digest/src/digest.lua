local ngx = ngx
local decode_base64 = ngx.decode_base64
local encode_base64 = ngx.encode_base64
local openssl = require "resty.openssl"
local openssl_digest = require "resty.openssl.digest"


local M = {}

function M.digest (body, alg)
  local digest = openssl_digest.new(alg)
  assert(digest:update(body))
  local hash = digest:final()
  return hash
end

function M.parse(digest)
  -- sha512=:<base64-encoded-digest>:
  local alg, digest_b64 = string.match(digest, "^(%w+)=:(.+):$")
  if not alg or not digest_b64 then
    return nil, nil, "Invalid Content-Digest header format"
  end

  local digest_bytes = decode_base64(digest_b64)
  if digest_bytes == nil then
    return nil, nil, "Failed to base64 decode digest"
  end

  return alg, digest_bytes, nil
end

return M