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
            signing_key_location = {
              type = "string",
              required = true
            }
          },
          {
            algorithm = {
              type = "string",
              one_of = {
                "sha256",
                "sha512",
              }           
            }
          }
        }
      }
    }
  }
}
