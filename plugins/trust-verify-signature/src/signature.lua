local jwks = require("kong.plugins.trust-verify-signature.jwks")
local cjson = require("cjson.safe")
local socket = require "socket"

local function cache_helper_issuer_get_keys(well_known_endpoint)
  kong.log.debug("Getting public keys from token issuer")
  local keys,
    err = jwks.get_issuer_keys(well_known_endpoint)
  if err then
    return nil, err
  end

  return {
    keys = keys,
    updated_at = socket.gettime()
  }
end

-- True when jwks_uri equals a configured prefix or continues past it at a "/"
-- boundary (so "https://host" does not match "https://host.evil.com").
local function jwks_uri_allowed(allowed_prefixes, jwks_uri)
  if type(allowed_prefixes) ~= "table" then
    return false
  end

  for _, prefix in pairs(allowed_prefixes) do
    if type(prefix) == "string" and #prefix > 0 then
      if jwks_uri == prefix then
        return true
      end
      if string.sub(jwks_uri, 1, #prefix) == prefix then
        local next_char = string.sub(jwks_uri, #prefix + 1, #prefix + 1)
        if string.sub(prefix, -1) == "/" or next_char == "/" then
          return true
        end
      end
    end
  end

  return false
end

local function verify_jwt_signature(conf, jwt, second_call)
  local jwks_endpoint = jwt.claims.jwks_uri
  if not jwks_endpoint then
    kong.log.warn("JWT token missing 'jwks_uri' claim")
    return false, {status = 401, message = "Signature missing 'jwks_uri' claim"}
  end

  if not jwks_uri_allowed(conf.allowed_jwks_uri_prefix, jwks_endpoint) then
    kong.log.warn("JWT jwks_uri not in allowed_jwks_uri_prefix: ", jwks_endpoint)
    return false, {status = 401, message = "JWKS URI not allowed"}
  end

  local jwks_cache_key = "trust_verify_signature_keys:" .. jwks_endpoint

  -- No TTL: keys stay until miss-driven refresh via iss_key_grace_period
  local public_keys,
    err = kong.cache:get(jwks_cache_key, nil, cache_helper_issuer_get_keys, jwks_endpoint)

  if not public_keys then
    if err then
      kong.log.err(err)
    end
    return false, {status = 401, message = "Unable to get public keys"}
  end

  local matching_jwk = public_keys.keys[jwt.header.kid]
  if matching_jwk then
    kong.log.warn("Found matching JWK for key ID: ", cjson.encode(matching_jwk))
    local success,
      sig_ok,
      message =
      pcall(
      function()
        return jwt:verify_signature(cjson.encode(matching_jwk))
      end
    )
    kong.log.warn("JWT signature verification result for key ID: ", jwt.header.kid, success, sig_ok, message)

    if not success then
      kong.log.warn("JWT signature verification failed for key ID: ", jwt.header.kid, message)
      return false, {status = 401, message = "Public key format error"}
    end

    if not sig_ok then
      kong.log.warn("JWT signature invalid for key ID: ", jwt.header.kid)
      return false, {status = 401, message = "Signature public key mismatch"}
    end

    return true
  end

  -- kid missing — possible key rotation. Refetch once if the cached keyset is
  -- older than iss_key_grace_period
  local since_last_update = socket.gettime() - public_keys.updated_at
  if not second_call and since_last_update > conf.iss_key_grace_period then
    kong.log.debug(
      "No matching JWK for key ID: ",
      jwt.header.kid,
      ". Keys updated last ",
      since_last_update,
      " seconds ago; refreshing keyset"
    )
    kong.cache:invalidate_local(jwks_cache_key)
    return verify_jwt_signature(conf, jwt, true)
  end

  kong.log.warn("No matching JWK found for key ID: ", jwt.header.kid)
  return false, {status = 401, message = "Signature public key not found"}
end

return {
  verify_jwt_signature = verify_jwt_signature
}
