local typedefs = require "kong.db.schema.typedefs"

return {
  name = "trust-sign",
  fields = {
    {protocols = typedefs.protocols_http},
    {
      config = {
        type = "record",
        fields = {
          {
            direction = {
              type = "string",
              one_of = {
                "request",
                "response"
              }
            }
          },
          {
            signature_label = {
              type = "string",
              required = true,
              default = "sig1"
            }
          },
          {
            signature_input = {
              type = "string",
              required = true
            }
          },
          {
            keyid = {
              type = "string",
              required = true
            }
          },
          {
            signature_header_key = {
              type = "string"
            }
          },
          {
            signing_key_location = {
              type = "string",
              required = true
            }
          },
          {
            alg = {
              type = "string",
              one_of = {
                "RS256",
                "RS512",
                "ES256",
                "ES512"
              }
            }
          },
          {
            hash_alg = {
              type = "string",
              one_of = {
                "sha256",
                "sha512"
              }
            }
          }
        }
      }
    }
  }
}
