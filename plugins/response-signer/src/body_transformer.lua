local cjson = require("cjson.safe").new()
local cjson_encode = cjson.encode
local cjson_decode = cjson.decode


local insert = table.insert
local type = type
local sub = string.sub
local gsub = string.gsub
local byte = string.byte
local match = string.match
local tonumber = tonumber
local pcall = pcall


cjson.decode_array_with_array_mt(true)


local noop = function() end


local QUOTE  = byte([["]])


local _M = {}


local function toboolean(value)
  if value == "true" then
    return true

  else
    return false
  end
end


local function cast_value(value, value_type)
  if value_type == "number" then
    return tonumber(value)

  elseif value_type == "boolean" then
    return toboolean(value)

  else
    return value
  end
end


local function json_value(value, json_type)
  local v = cjson_encode(value)
  if v and byte(v, 1) == QUOTE and byte(v, -1) == QUOTE then
    v = gsub(sub(v, 2, -2), [[\"]], [["]]) -- To prevent having double encoded quotes
  end

  v = v and gsub(v, [[\/]], [[/]]) -- To prevent having double encoded slashes

  if json_type then
    v = cast_value(v, json_type)
  end

  return v
end


local function parse_json(body)
  if body then
    local ok, res = pcall(cjson_decode, body)
    if ok then
      return res
    end
  end
end


local function append_value(current_value, value)
  local current_value_type = type(current_value)

  if current_value_type == "string" then
    return { current_value, value }
  end

  if current_value_type == "table" then
    insert(current_value, value)
    return current_value
  end

  return { value }
end

local function iter(config_array)
  if type(config_array) ~= "table" then
    return noop
  end

  return function(config_array, i)
    i = i + 1

    local current_pair = config_array[i]
    if current_pair == nil then -- n + 1
      return nil
    end

    local current_name, current_value = match(current_pair, "^([^:]+):*(.-)$")
    if current_value == "" then
      current_value = nil
    end

    return i, current_name, current_value
  end, config_array, 0
end


function _M.transform_json_body(conf, buffered_data)
  local json_body = parse_json(buffered_data)
  if json_body == nil then
    return nil, "failed parsing json body"
  end

  -- add signing key to body
  local sign = require "kong.plugins.response-signer.sign"
  local sign_jwt = sign.sign_jwt
  local jwt_token, err = sign_jwt(conf, json_body)
  if err then
    return nil, "failed signing jwt: " .. err
  end

  return jwt_token
end


return _M
