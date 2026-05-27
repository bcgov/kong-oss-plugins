local cjson = require "cjson.safe"
local openssl_pkey = require "resty.openssl.pkey"

local _M = {}

local function pem_to_jwk(pem)
  local ok, pkey_or_err = pcall(openssl_pkey.new, pem)
  if not ok or not pkey_or_err then
    return nil, "failed to parse PEM key: " .. tostring(pkey_or_err)
  end
  local pkey = pkey_or_err
  local ok2, jwk_str_or_err = pcall(function()
    return pkey:tostring("public", "JWK")
  end)
  if not ok2 or not jwk_str_or_err then
    return nil, "failed to export JWK: " .. tostring(jwk_str_or_err)
  end
  local jwk, err = cjson.decode(jwk_str_or_err)
  if err then
    return nil, "failed to decode exported JWK: " .. err
  end
  return jwk, nil
end

local function build_key_entry(key_entity)
  local jwk

  if key_entity.jwk and key_entity.jwk ~= ngx.null then
    local decoded, err = cjson.decode(key_entity.jwk)
    if err then
      return nil, "failed to decode stored JWK: " .. err
    end
    jwk = decoded
  elseif key_entity.pem and key_entity.pem ~= ngx.null then
    local pub = key_entity.pem.public_key
    if not pub or pub == ngx.null then
      return nil, "no public_key in pem field"
    end
    local converted, err = pem_to_jwk(pub)
    if err then
      return nil, err
    end
    jwk = converted
  else
    return nil, "key entity has neither jwk nor pem fields"
  end

  local kid = key_entity.kid
  if not kid or kid == ngx.null or kid == "" then
    kid = key_entity.name
  end
  if kid and kid ~= ngx.null then
    jwk.kid = kid
  end

  return jwk, nil
end

function _M.build_jwks(key_set_name)
  local set_id

  if key_set_name then
    local key_set, err = kong.db.key_sets:select_by_name(key_set_name)
    if err then
      return nil, 500, "error looking up keyset: " .. err
    end
    if not key_set then
      return nil, 404, "keyset not found: " .. key_set_name
    end
    set_id = key_set.id
  end

  local keys_list = {}

  for key_entity, err in kong.db.keys:each() do
    if err then
      kong.log.warn("error iterating keys: ", err)
      break
    end

    if set_id then
      local entity_set_id = key_entity.set and key_entity.set.id
      if entity_set_id ~= set_id then
        goto continue
      end
    end

    local jwk, build_err = build_key_entry(key_entity)
    if build_err then
      kong.log.warn("skipping key '", key_entity.name, "': ", build_err)
    else
      keys_list[#keys_list + 1] = jwk
    end

    ::continue::
  end

  return { keys = keys_list }, 200, nil
end

return _M
