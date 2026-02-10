local typedefs = require "kong.db.schema.typedefs"

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
              default = 60
            }
          },
          {
            key_id = {
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
