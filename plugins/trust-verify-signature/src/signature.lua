local jwks = require("kong.plugins.trust-verify-signature.jwks")

local function custom_helper_issuer_get_keys(well_known_endpoint, cafile)
  kong.log.debug("Getting public keys from token issuer")
  local keys,
    err = jwks.get_issuer_keys(well_known_endpoint, cafile)
  if err then
    return nil, err
  end

  return {
    keys = keys,
    updated_at = socket.gettime()
  }
end

local function validate_token_signature(conf, jwt, second_call)
  local jwks_cache_key = "trust_verify_signature_keys"

  local public_keys,
    err = kong.cache:get(jwks_cache_key, nil, custom_helper_issuer_get_keys, conf.jwks_endpoint)

  if not public_keys then
    if err then
      kong.log.err(err)
    end
    return false, {status = 403, message = "Unable to get public keys"}
  end

  local matching_jwk = public_keys.keys[jwt.header.kid]
  if matching_jwk then
    if jwt:verify_signature(matching_jwk) then
      return true
    else
      kong.log.warn("JWT signature verification failed for key ID: ", jwt.header.kid)
      return false, {status = 401, message = "Signature public key mismatch"}
    end
  end

  -- -- We could not validate signature, try to get a new keyset?
  local since_last_update = socket.gettime() - public_keys.updated_at
  if not second_call and since_last_update > conf.iss_key_grace_period then
    kong.log.debug("Could not validate signature. Keys updated last " .. since_last_update .. " seconds ago")
    -- can it be that the signature key of the issuer has changed ... ?
    -- invalidate the old keys in kong cache and do a current lookup to the signature keys
    -- of the token issuer
    kong.cache:invalidate_local(jwks_cache_key)
    return validate_token_signature(conf, jwt, true)
  end

  return false, {status = 401, message = "Invalid trust signature"}
end

return {
  validate_token_signature = validate_token_signature
}
