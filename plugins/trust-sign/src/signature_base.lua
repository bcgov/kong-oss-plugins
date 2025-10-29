local pl_file = require "pl.file"
local openssl_digest = require "resty.openssl.digest"
local openssl_pkey = require "resty.openssl.pkey"

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
    local components_str = signature_params:match('^%(([^)]+)%)')
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

local function get_private_key_location(conf)
  return conf.signing_key_location
end

--- Read contents of file from given location
-- @param file_location the file location
-- @return the file contents
local function read_from_file(file_location)
  local content, err = pl_file.read(file_location)
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
  local pkey, err = kong.cache:get(key, { ttl = 0 }, read_from_file, location)

  if err then
    ngx.log(ngx.ERR, "Could not retrieve pkey: ", err)
    return
  end

  return pkey
end

function M.sign(conf, input, algorithm)
  local kong_private_key = get_kong_key("pkey", get_private_key_location(conf))

  local digest = openssl_digest.new(algorithm)
  assert(digest:update(input))
  local signature = assert(openssl_pkey.new(kong_private_key):sign(digest))
  return signature
end

return M