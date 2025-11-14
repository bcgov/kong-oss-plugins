local resty_sha256 = require "resty.sha256"
local str = require "resty.string"
local kong = kong
local pl_file = require "pl.file"
local json = require "cjson"
local openssl_digest = require "resty.openssl.digest"
local openssl_pkey = require "resty.openssl.pkey"
local table_concat = table.concat
local base64 = require "ngx.base64"
local encode_base64url = base64.encode_base64url
local env_private_key_location = os.getenv("KONG_SIGNING_CERT_KEY")
local env_public_key_location = os.getenv("KONG_SIGNING_CERT")
local utils = require "kong.tools.utils"
local _M = {}

--- Get the private key location either from the environment or from configuration
-- @param conf the kong configuration
-- @return the private key location
local function get_private_key_location(conf)
  if env_private_key_location then
    return env_private_key_location
  end
  return conf.private_key_location
end

--- Get the public key location either from the environment or from configuration
-- @param conf the kong configuration
-- @return the public key location
local function get_public_key_location(conf)
  if env_public_key_location then
    return env_public_key_location
  end
  return conf.public_key_location
end

local function pem_to_x5c(pem_cert)
  -- Remove PEM headers and footers
  local cert_data = pem_cert:gsub("%-%-%-%-%-BEGIN CERTIFICATE%-%-%-%-%-", "")
  cert_data = cert_data:gsub("%-%-%-%-%-END CERTIFICATE%-%-%-%-%-", "")

  -- Remove all whitespace (newlines, spaces, tabs)
  cert_data = cert_data:gsub("%s", "")

  return cert_data
end

--- base 64 encoding
-- @param input String to base64 encode
-- @return Base64 encoded string
local function b64_encode(input)
  local result = encode_base64url(input)
  -- result = result:gsub("+", "-"):gsub("/", "_"):gsub("=", "")
  return result
end

--- Read contents of file from given location
-- @param file_location the file location
-- @return the file contents
local function read_from_file(file_location)
  local content,
    err = pl_file.read(file_location)
  if not content then
    ngx.log(ngx.ERR, "Could not read file contents", err)
    return nil, err
  end
  return content
end

--- Get the Kong key either from cache or the given `location`
-- @param key the cache key to lookup first
-- @param location the location of the key file
-- @return the key contents
local function get_kong_key(key, location)
  -- This will add a non expiring TTL on this cached value
  -- https://github.com/thibaultcha/lua-resty-mlcache/blob/master/README.md
  local pkey,
    err = kong.cache:get(key, {ttl = 0}, read_from_file, location)

  if err then
    ngx.log(ngx.ERR, "Could not retrieve pkey: ", err)
    return
  end

  return pkey
end

--- Base64 encode the JWT token
-- @param payload the payload of the token
-- @param key the key to sign the token with
-- @return the encoded JWT token
local function encode_jwt_token(conf, payload, key)
  local header = {
    alg = conf.alg
    -- x5c = {
    --   pem_to_x5c(get_kong_key("pubder", get_public_key_location(conf)))
    -- }
  }
  if conf.keyid then
    header.kid = conf.keyid
  end
  local segments = {
    b64_encode(json.encode(header)),
    b64_encode(json.encode(payload))
  }
  local signing_input = table_concat(segments, ".")

  local signature =
    assert(
    openssl_pkey.new(key):sign(
      signing_input,
      conf.hash_alg,
      nil,
      {
        ecdsa_use_raw = true
      }
    )
  )
  segments[#segments + 1] = b64_encode(signature)
  return table_concat(segments, ".")
end

--- Build the payload hash
-- @return SHA-256 hash of the request body data
local function build_payload_hash(req_body)
  local payload_digest = ""
  if req_body then
    local sha256 = resty_sha256:new()
    sha256:update(req_body)
    payload_digest = sha256:final()
  end
  return str.to_hex(payload_digest)
end

--- Build the JWT token payload based off the `payload_hash`
-- @param conf the configuration
-- @param payload_hash the payload hash
-- @return the JWT payload (table)
local function build_jwt_payload(conf, payload)
  payload.jti = utils.uuid()
  payload.iat = ngx.time()

  -- if ngx.ctx.service then
  --   payload.aud = ngx.ctx.service.name
  -- end

  -- local consumer = kong.client.get_consumer()
  -- if consumer then
  --   payload.consumerid = consumer.id
  --   payload.consumername = consumer.username
  -- end

  return payload
end

-- Encode the JWT token
function _M.sign_jwt(conf, manifest)
  local jwt_payload = build_jwt_payload(conf, manifest)
  local kong_private_key = get_kong_key("trust_sign_pkey_" .. conf.private_key_location, get_private_key_location(conf))
  local jwt = encode_jwt_token(conf, jwt_payload, kong_private_key)
  return jwt
end

return _M
