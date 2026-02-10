local typedefs = require "kong.db.schema.typedefs"

return {
  name = "trust-kms",
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
            operation = {
              type = "string",
              default = "create_key",
              required = true,
              one_of = {
                "create_key",
                "sign",
                "verify"
              }
            }
          },
          {
            key_id = {
              type = "string",
              required = false
            }
          },
          {
            signature_algorithm = {
              type = "string",
              default = "ECDSA_SHA_512",
              one_of = {
                "RSASSA_PSS_SHA_256",
                "RSASSA_PSS_SHA_384",
                "RSASSA_PSS_SHA_512",
                "ECDSA_SHA_256",
                "ECDSA_SHA_384",
                "ECDSA_SHA_512"
              }
            }
          },
          {
            signature_header_key = {
              type = "string"
            }
          }
        }
      }
    }
  }
}
