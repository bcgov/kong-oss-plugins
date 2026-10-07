local pl_file = require "pl.file"
local x509 = require "resty.openssl.x509"
local openssl_digest = require "resty.openssl.digest"
local openssl_pkey = require "resty.openssl.pkey"
local env_private_key_location = os.getenv("KONG_SIGNING_CERT_KEY")
local env_public_key_location = os.getenv("KONG_SIGNING_CERT")

local M = {}

-- RFC 9421: Signature Base String
function M.get_signature_base(headers, kong_request, signature_label, signature_input)
  -- Extract signature parameters from Signature-Input header
  if not signature_input then
    return nil, "Missing signature parameters"
  end

  local signature_params = signature_input:match(signature_label .. "=(.+)")
  if not signature_params then
    return nil, "Expecting " .. signature_label .. " signature parameters"
  end

  -- Parse components from signature input (RFC 9421)
  local components_str = signature_params:match("^%(([^)]+)%)")
  if not components_str then
    return nil, "Invalid signature format"
  end

  -- Extract component names
  local components = {}
  for component in components_str:gmatch('"([^"]+)"') do
    table.insert(components, component)
  end

  -- Build signature message according to RFC 9421 (only include specified components)
  local message_parts = {}
  for _, component in ipairs(components) do
    if component == "@authority" then
      local authority_value = headers["host"] or kong_request.get_host()
      table.insert(message_parts, '"@authority": ' .. authority_value)
    elseif component == "@method" then
      table.insert(message_parts, '"@method": ' .. kong_request.get_method())
    elseif component == "@path" then
      table.insert(message_parts, '"@path": ' .. kong_request.get_path())
    else
      local header_value = headers[component]
      if header_value then
        table.insert(message_parts, '"' .. component .. '": ' .. header_value)
      elseif kong_request.get_header(component) then
        table.insert(message_parts, '"' .. component .. '": ' .. kong_request.get_header(component))
      else
        return nil, "Missing required header: " .. component
      end
    end
  end

  -- Always add @signature-params at the end (RFC 9421 requirement)
  table.insert(message_parts, '"@signature-params": ' .. signature_params)

  local message = table.concat(message_parts, "\n")
  return message
end

local function get_public_key_location(conf)
  return conf.public_key_location or env_public_key_location
end

local function get_private_key_location(conf)
  return conf.private_key_location or env_private_key_location
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

function M.sign(conf, input, hash_alg)
  local kong_private_key = get_kong_key("trust-sign-pkey", get_private_key_location(conf))

  kong.log.warn("Signing with hash algorithm: ", hash_alg)
  kong.log.warn("Signing with key: ", get_private_key_location(conf))

  local digest,
    err = openssl_digest.new(hash_alg)
  if err then
    kong.log.err("Failed to create digest: ", err)
    return nil
  end

  assert(digest:update(input))

  local pk = openssl_pkey.new(kong_private_key)

  local signature = assert(pk:sign(digest))
  kong.log.warn("Signature length: ", #signature)

  local vdigest = openssl_digest.new(hash_alg)
  assert(vdigest:update(input))

  local ok,
    err = pk:verify(signature, vdigest)
  kong.log.warn("Verify: ", ok, err)

  if not ok then
    kong.log.err("Signature verification failed: ", err)
    return nil
  end

  return signature
end

function M.verify(conf, signature, input, hash_alg)
  local kong_public_key = get_kong_key("trust-sign-pubkey", get_public_key_location(conf))

  kong.log.warn("Verifying with hash algorithm: ", hash_alg)
  kong.log.warn("Verifying with key: ", get_public_key_location(conf))

  local vdigest = openssl_digest.new(hash_alg)
  assert(vdigest:update(input))

  local cert,
    err = x509.new(kong_public_key, "PEM")
  local pk,
    err = cert:get_pubkey()
  if err then
    kong.log.err("Failed to create public key object: ", err)
    return nil
  end

  local ok,
    err = pk:verify(signature, vdigest)
  kong.log.warn("Verify: ", ok, err)

  if not ok then
    kong.log.err("Signature verification failed: ", err)
    return nil
  end

  return signature
end

return M
