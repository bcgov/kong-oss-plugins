-- handler.lua: trust-registry-ai
-- Serves registered public keys as a JWKS endpoint (RFC 7517).
-- FR-001: GET /.well-known/jwks.json returns all registered keys.
-- FR-002: GET /keysets/{key_set}/.well-known/jwks.json filters by keyset.
local cjson      = require "cjson"
local kong_meta  = require "kong.meta"
local pem_to_jwk = require "kong.plugins.trust-registry-ai.pem_to_jwk"

local kong = kong

local TrustRegistryAIHandler = {
  PRIORITY = 1000,
  VERSION  = kong_meta.version
}

-- Build a JWK table from a Kong key entity.
-- FR-005: JWK must include the kid field.
-- FR-006: PEM keys are converted to JWK.
-- FR-007: JWK keys are included as-is.
-- FR-011: Unconvertible keys are omitted and the failure is logged.
local function key_to_jwk(key)
  if key.jwk then
    local ok, decoded = pcall(cjson.decode, key.jwk)
    if ok and type(decoded) == "table" then
      decoded.kid = key.kid
      return decoded
    end
    kong.log.err("trust-registry-ai: failed to decode JWK for key '", key.kid, "'")
    return nil
  end

  if key.pem and key.pem.public_key then
    local jwk, err = pem_to_jwk.pem_to_jwk(key.pem.public_key, key.kid)
    if not jwk then
      kong.log.err(
        "trust-registry-ai: failed to convert PEM to JWK for key '",
        key.kid, "': ", err
      )
    end
    return jwk
  end

  return nil
end

-- Collect all keys from an iterator into the keys array.
local function collect_keys(iterator, keys)
  for key, err in iterator do
    if err then
      kong.log.err("trust-registry-ai: error iterating keys: ", err)
      break
    end
    local jwk = key_to_jwk(key)
    if jwk then
      keys[#keys + 1] = jwk
    end
  end
end

function TrustRegistryAIHandler:access(conf)
  local keys = {}

  -- FR-002: Extract keyset name from request path.
  -- Route: ~/keysets/(?<key_set>.+)/.well-known/jwks.json
  local path = kong.request.get_path()
  local key_set_name = path:match("^/keysets/(.+)/%.well%-known/jwks%.json$")

  if key_set_name then
    -- Keyset-scoped request
    local kset, err = kong.db.key_sets:select_by_name(key_set_name)
    if err then
      kong.log.err(
        "trust-registry-ai: failed to look up key set '", key_set_name, "': ", err
      )
      return kong.response.exit(
        500, { message = "Internal error" },
        { ["Content-Type"] = "application/json" }
      )
    end

    -- FR-009: Named keyset not found → 404
    if not kset then
      return kong.response.exit(
        404, { message = "Key set not found" },
        { ["Content-Type"] = "application/json" }
      )
    end

    collect_keys(kong.db.keys:each_for_set({ id = kset.id }), keys)
  else
    -- FR-001: All-keys request
    collect_keys(kong.db.keys:each(), keys)
  end

  -- FR-003: Response is a valid JWKS ({"keys": [...]})
  -- FR-004: Content-Type is application/json
  -- FR-010: Empty keys array returned when no keys match
  return kong.response.exit(
    200, { keys = keys },
    { ["Content-Type"] = "application/json" }
  )
end

return TrustRegistryAIHandler
