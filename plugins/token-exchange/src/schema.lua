local typedefs = require "kong.db.schema.typedefs"

local function validate_single_scope(value)
  if value == "" or value:find("%s") then
    return nil, "must contain exactly one non-empty OAuth scope value"
  end
  return true
end

return {
  name = "token-exchange",
  fields = {
    {protocols = typedefs.protocols_http},
    {
      config = {
        type = "record",
        fields = {
          {
            private_key_location = {
              type = "string",
              required = true
            }
          },
          {
            client_id = {
              type = "string",
              required = true
            }
          },
          {
            token_endpoint = {
              type = "string",
              required = true
            }
          },
          {
            algorithm = {
              type = "string",
              default = "RS256",
              one_of = {
                "RS256",
                "RS384",
                "RS512",
                "ES256",
                "ES384",
                "ES512"
              }
            }
          },
          {
            expiration = {
              type = "number",
              default = 60,
              gt = 0
            }
          },
          {
            timeout = {
              type = "number",
              default = 10000
            }
          },
          {
            key_id = {
              type = "string",
              required = false
            }
          },
          {
            keyset_name = {
              type = "string",
              required = false
            }
          },
          {
            scopes = {
              type = "array",
              elements = {
                type = "string"
              },
              default = {}
            }
          },
          {
            scope_source = {
              type = "string",
              default = "configured",
              one_of = {
                "configured",
                "verified_subject_token"
              }
            }
          },
          {
            target_privacy_zone_scope = {
              type = "string",
              required = false,
              custom_validator = validate_single_scope
            }
          },
          {
            audience = {
              type = "string",
              required = false
            }
          }
        }
      }
    }
  }
}
