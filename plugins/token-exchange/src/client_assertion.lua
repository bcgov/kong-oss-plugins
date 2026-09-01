local http = require "resty.http"
local cjson = require "cjson.safe"
local base64 = require "ngx.base64"
local encode_base64url = base64.encode_base64url
local openssl_pkey = require "resty.openssl.pkey"
local table_concat = table.concat
local kong = kong
local jwk_sign = require("kong.plugins.trust-sign.sign")

local digest_by_algorithm = {
  RS256 = "sha256",
  RS384 = "sha384",
  RS512 = "sha512",
  ES256 = "sha256",
  ES384 = "sha384",
  ES512 = "sha512"
}

local key_type_oid_by_family = {
  RS = "1.2.840.113549.1.1.1",
  ES = "1.2.840.10045.2.1"
}

--- Generate a unique identifier (jti) for the JWT
-- @return string A unique identifier
local function generate_jti()
  local random = require "resty.random"
  local str = require "resty.string"
  local bytes = random.bytes(16)
  return str.to_hex(bytes)
end

--- Base64 encode the JWT token
-- @param payload the payload of the token
-- @param key the key to sign the token with
-- @return the encoded JWT token
local function encode_jwt_token(conf, payload, key)
  local algorithm = conf.algorithm or "RS256"
  local digest = assert(digest_by_algorithm[algorithm], "unsupported signing algorithm")
  local private_key, key_err = openssl_pkey.new(key)
  if not private_key then
    return nil, "unable to parse private key: " .. (key_err or "unknown error")
  end

  local key_type, type_err = private_key:get_key_type()
  if not key_type then
    return nil, "unable to determine private key type: " .. (type_err or "unknown error")
  end

  local expected_key_type = key_type_oid_by_family[algorithm:sub(1, 2)]
  if key_type.id ~= expected_key_type then
    return nil, "private key type does not match signing algorithm " .. algorithm
  end

  local header = {
    alg = algorithm
    -- x5c = {
    --   pem_to_x5c(get_kong_key("pubder", get_public_key_location(conf)))
    -- }
  }
  if conf.key_id then
    header.kid = conf.key_id
  end

  local segments = {
    encode_base64url(cjson.encode(header)),
    encode_base64url(cjson.encode(payload))
  }
  local signing_input = table_concat(segments, ".")

  local signature =
    assert(
    private_key:sign(
      signing_input,
      digest,
      nil,
      {
        ecdsa_use_raw = true
      }
    )
  )
  segments[#segments + 1] = encode_base64url(signature)
  return table_concat(segments, ".")
end

--- Create a JWT client assertion for Keycloak authentication
-- @param config table Configuration containing:
--   - client_id: The client ID
--   - token_endpoint: The Keycloak token endpoint URL
--   - private_key_location: The private key in PEM format (for signing)
--   - algorithm: JWT signing algorithm (default: "RS256")
--   - expiration: Token expiration time in seconds (default: 60)
-- @return string|nil The signed JWT client assertion, or nil on error
-- @return string|nil Error message if creation failed
function create_client_assertion(config)
  if not config then
    return nil, "configuration is required"
  end

  if not config.client_id then
    return nil, "client_id is required"
  end

  if not config.token_endpoint then
    return nil, "token_endpoint is required"
  end

  if not config.private_key_location then
    return nil, "private_key_location is required"
  end

  local algorithm = config.algorithm or "RS256"
  local expiration = config.expiration or 60
  local now = ngx.time()

  -- Construct JWT payload following Keycloak requirements
  local payload = {
    iss = config.client_id, -- Issuer: client ID
    sub = config.client_id, -- Subject: client ID
    aud = config.token_endpoint, -- Audience: token endpoint
    jti = generate_jti(), -- Unique token identifier
    exp = now + expiration, -- Expiration time
    iat = now -- Issued at time
  }

  -- Create and sign the JWT. Do not mutate the plugin config in place.
  local signing_conf = {}
  for key, value in pairs(config) do
    signing_conf[key] = value
  end

  if (not signing_conf.key_id or signing_conf.key_id == "") and signing_conf.keyset_name then
    local resolved_kid, resolve_err =
      jwk_sign.resolve_kid(
      {
        keyid = signing_conf.key_id,
        keyset_name = signing_conf.keyset_name,
        private_key_location = signing_conf.private_key_location
      }
    )
    if not resolved_kid then
      return nil, resolve_err or "unable to resolve signing kid"
    end
    signing_conf.key_id = resolved_kid
  end

  local private_key_location = jwk_sign.get_private_key_location(signing_conf)
  local kong_private_key =
    jwk_sign.get_kong_key("token_exchange_pkey_" .. signing_conf.private_key_location, private_key_location)
  if not kong_private_key then
    return nil, "unable to read private key"
  end

  local jwt_token, err = encode_jwt_token(signing_conf, payload, kong_private_key)

  if not jwt_token then
    return nil, err or "unable to prepare client assertion"
  end

  return jwt_token
end

return {
  create_client_assertion = create_client_assertion
}
