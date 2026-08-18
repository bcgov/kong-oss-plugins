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

local function normalize_pem(pem)
  if not pem or pem == ngx.null then
    return nil
  end
  return pem:gsub("%-%-%-%-%-[^-]+%-%-%-%-%-", ""):gsub("%s", "")
end

local function public_pem_from_material(material)
  local pkey, err = openssl_pkey.new(material)
  if not pkey then
    return nil, err
  end
  return pkey:to_PEM("public")
end

--- Return true when `key` is the public half of `private_pem`.
local function public_key_matches(private_pem, key)
  local want, err = public_pem_from_material(private_pem)
  if not want then
    return false, err
  end
  want = normalize_pem(want)

  if key.pem and key.pem.public_key and key.pem.public_key ~= ngx.null then
    return normalize_pem(key.pem.public_key) == want
  end

  if key.jwk and key.jwk ~= ngx.null then
    local jwk = key.jwk
    if type(jwk) == "string" then
      jwk = json.decode(jwk)
    end
    local got, jwk_err = public_pem_from_material(jwk)
    if not got then
      return false, jwk_err
    end
    return normalize_pem(got) == want
  end

  return false
end

--- Pick the unique matching kid from a list of Kong key entities.
local function match_kid_for_keys(private_pem, keys)
  local matches = {}
  for _, key in ipairs(keys or {}) do
    local ok = public_key_matches(private_pem, key)
    if ok and key.kid then
      matches[#matches + 1] = key.kid
    end
  end
  if #matches == 0 then
    return nil, "no keyset entry matches the mounted private key"
  end
  if #matches > 1 then
    return nil, "multiple keyset entries match the mounted private key"
  end
  return matches[1]
end

local function load_keyset_keys(keyset_name)
  if not kong or not kong.db or not kong.db.key_sets or not kong.db.keys then
    return nil, "kong key set dao is unavailable"
  end

  local keyset, err = kong.db.key_sets:select_by_name(keyset_name)
  if err then
    return nil, err
  end
  if not keyset then
    return nil, "key set not found: " .. tostring(keyset_name)
  end

  local found = {}
  if kong.db.keys.page_for_set then
    local size = 100
    local offset
    repeat
      local page, page_err, next_offset = kong.db.keys:page_for_set(keyset, size, offset)
      if page_err then
        return nil, page_err
      end
      if page then
        for i = 1, #page do
          found[#found + 1] = page[i]
        end
      end
      offset = next_offset
    until not offset
  else
    for key, each_err in kong.db.keys:each() do
      if each_err then
        return nil, each_err
      end
      local set_id = key.set and (key.set.id or key.set)
      if set_id == keyset.id then
        found[#found + 1] = key
      end
    end
  end
  return found
end

--- Resolve the JWT kid: explicit config.keyid wins; otherwise match the
-- mounted private key against Kong keyset `config.keyset_name`.
local function resolve_kid(conf)
  if conf.keyid and conf.keyid ~= "" then
    return conf.keyid
  end
  if not conf.keyset_name or conf.keyset_name == "" then
    return nil, "keyid or keyset_name is required"
  end

  local location = get_private_key_location(conf)
  local private_pem = get_kong_key("trust_sign_pkey_" .. tostring(location), location)
  if not private_pem then
    return nil, "unable to load private key"
  end

  local cache_key = "trust_sign_kid:" .. conf.keyset_name .. ":" .. ngx.md5(private_pem)
  local loader = function()
    local keys, load_err = load_keyset_keys(conf.keyset_name)
    if not keys then
      return nil, load_err
    end
    return match_kid_for_keys(private_pem, keys)
  end

  if kong and kong.cache then
    return kong.cache:get(cache_key, {ttl = 30}, loader)
  end
  return loader()
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
  local kid, kid_err = resolve_kid(conf)
  if not kid then
    ngx.log(ngx.ERR, "trust-sign kid resolution failed: ", kid_err)
    return nil, kid_err
  end
  header.kid = kid
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
local function sign_jwt(conf, manifest)
  local jwt_payload = build_jwt_payload(conf, manifest)
  local kong_private_key = get_kong_key("trust_sign_pkey_" .. conf.private_key_location, get_private_key_location(conf))
  local jwt, err = encode_jwt_token(conf, jwt_payload, kong_private_key)
  return jwt, err
end

return {
  sign_jwt = sign_jwt,
  get_kong_key = get_kong_key,
  get_private_key_location = get_private_key_location,
  resolve_kid = resolve_kid,
  match_kid_for_keys = match_kid_for_keys,
}
