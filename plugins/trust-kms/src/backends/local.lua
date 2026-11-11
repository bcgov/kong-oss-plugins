local ltn12 = require("ltn12")
local json = require("cjson")

local openssl_pkey = require "resty.openssl.pkey"
local jwk_sign = require("kong.plugins.trust-sign.sign")
local digest_mod = require("kong.plugins.trust-sign.digest")
local env_private_key_location = os.getenv("KONG_SIGNING_CERT_KEY")
local env_public_key_location = os.getenv("KONG_SIGNING_CERT")
local string = require("resty.string")

function create_key()
  return get_private_key()
end

function disable_key(key_id)
end

function sign(key_id, message, algo)
  -- use the private key to sign the message using the algo
  local private_key = get_private_key()
  if private_key == nil then
    return nil, "Failed to get private key for signing"
  end

  local signature_bytes =
    assert(
    openssl_pkey.new(private_key):sign(
      message
      -- "sha256",
      -- nil,
      -- {
      --   ecdsa_use_raw = true
      -- }
    )
  )
  if not signature_bytes then
    return nil, "Failed to sign message: " .. err
  end
  return signature_bytes
end

function verify(key_id, message, signature, algo)
  -- verify the signature using the public key
  local public_key = get_public_key(key_id)
  if public_key == nil then
    return nil, "Failed to get public key for verification"
  end
  local result,
    err =
    public_key:verify(
    signature,
    message
    -- "sha256",
    -- nil,
    -- {
    --   ecdsa_use_raw = true
    -- }
  )
  if err then
    return nil, "Failed to verify signature: " .. err
  end
  return result
end

function get_public_key(key_id)
  -- get public key
  kong.log.err("Getting public key from local signing certificate at: " .. env_public_key_location)

  local x509 = require "resty.openssl.x509"
  local pkey = require "resty.openssl.pkey"

  -- Load a certificate file and extract its public key
  local f = io.open(env_public_key_location, "rb")
  local cert_data = f:read("*all")
  f:close()

  local cert,
    err = x509.new(cert_data, "PEM")
  if err then
    return nil, "failed to load cert: " .. err
  end

  local pubkey,
    err = cert:get_pubkey()
  if err then
    return nil, "failed to get pubkey: " .. err
  end

  return pubkey
end

function get_private_key()
  -- get private key from local signing certificate
  kong.log.err("Getting private key from local signing certificate at: " .. env_private_key_location)
  local kong_private_key =
    jwk_sign.get_kong_key("token_exchange_pkey_" .. env_private_key_location, env_private_key_location)
  if kong_private_key == nil then
    return nil, "failed to read private key from " .. tostring(env_private_key_location)
  end

  local pkey,
    err = openssl_pkey.new(kong_private_key)
  if pkey == nil then
    return nil, "failed to parse private key PEM: " .. tostring(err)
  end
  return pkey
end

return {
  create_key = create_key,
  disable_key = disable_key,
  sign = sign,
  verify = verify,
  get_public_key = get_public_key
}
