local jwks = require("kong.plugins.trust-verify-signature.jwks")
local cjson = require("cjson.safe")

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

local function verify_jwt_signature(conf, jwt, second_call)
  local jwks_cache_key = "trust_verify_signature_keys"

  local public_keys,
    err = kong.cache:get(jwks_cache_key, {ttl = 15}, cache_helper_issuer_get_keys, conf.jwks_endpoint)

  if not public_keys then
    if err then
      kong.log.err(err)
    end
    return false, {status = 403, message = "Unable to get public keys"}
  end

  local matching_jwk = public_keys.keys[jwt.header.kid]
  if matching_jwk then
    kong.log.warn("Found matching JWK for key ID: ", cjson.encode(matching_jwk))
    local success,
      message =
      pcall(
      function()
        return jwt:verify_signature(cjson.encode(matching_jwk))
      end
    )

    if not success then
      kong.log.warn("JWT signature verification failed for key ID: ", jwt.header.kid, message)
      return false, {status = 401, message = "Signature public key mismatch"}
    end

    return true
  else
    kong.log.warn("No matching JWK found for key ID: ", jwt.header.kid)
    return false, {status = 401, message = "Signature public key not found"}
  end

  -- -- We could not validate signature, try to get a new keyset?
  local since_last_update = socket.gettime() - public_keys.updated_at
  if not second_call and since_last_update > conf.iss_key_grace_period then
    kong.log.debug("Could not validate signature. Keys updated last " .. since_last_update .. " seconds ago")
    -- can it be that the signature key of the issuer has changed ... ?
    -- invalidate the old keys in kong cache and do a current lookup to the signature keys
    -- of the token issuer
    kong.cache:invalidate_local(jwks_cache_key)
    return verify_jwt_signature(conf, jwt, true)
  end

  return false, {status = 401, message = "Invalid trust signature"}
end

return {
  verify_jwt_signature = verify_jwt_signature
}
