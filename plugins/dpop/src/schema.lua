local typedefs = require "kong.db.schema.typedefs"
local validate_header_name = require("kong.tools.http").validate_header_name

local function validate_headers(pair, validate_value)
  local name,
    value = pair:match("^([^:]+):*(.-)$")
  if validate_header_name(name) == nil then
    return nil, string.format("'%s' is not a valid header", tostring(name))
  end

  if validate_value then
    if validate_header_name(value) == nil then
      return nil, string.format("'%s' is not a valid header", tostring(value))
    end
  end
  return true
end

local function validate_colon_headers(pair)
  return validate_headers(pair, true)
end

local string_array = {
  type = "array",
  default = {},
  required = true,
  elements = {type = "string"}
}

local colon_string_array = {
  type = "array",
  default = {},
  required = true,
  elements = {type = "string", match = "^[^:]+:.*$"}
}

local string_record = {
  type = "record",
  fields = {
    {json = string_array},
    {headers = string_array}
  }
}

local colon_string_record = {
  type = "record",
  fields = {
    {json = colon_string_array},
    {
      json_types = {
        description = "List of JSON type names. Specify the types of the JSON values returned when appending\nJSON properties. Each string element can be one of: boolean, number, or string.",
        type = "array",
        default = {},
        required = true,
        elements = {
          type = "string",
          one_of = {"boolean", "number", "string"}
        }
      }
    },
    {headers = colon_string_array}
  }
}

local colon_headers_array = {
  type = "array",
  default = {},
  required = true,
  elements = {type = "string", match = "^[^:]+:.*$", custom_validator = validate_colon_headers}
}

local colon_rename_strings_array_record = {
  type = "record",
  fields = {
    {json = colon_string_array},
    {headers = colon_headers_array}
  }
}

return {
  name = "dpop",
  fields = {
    {protocols = typedefs.protocols_http},
    {
      config = {
        type = "record",
        fields = {
          {max_age = {type = "number", default = 60}},
          {clock_skew = {type = "number", default = 60}},
          {
            allowed_algorithms = {
              type = "array",
              elements = {type = "string"},
              default = {"RS256", "ES256", "PS256"}
            }
          },
          {nonce_cache_ttl = {type = "number", default = 300}},
          {anonymous = {type = "string", uuid = true}}
        }
      }
    }
  }
}
