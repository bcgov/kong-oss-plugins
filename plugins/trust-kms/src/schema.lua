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
            jwks_uri = {
              type = "string"
            }
          },
          {
            signature_header_key = {
              type = "string"
            }
          },
          {
            private_key_location = {
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
            keyid = {
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
          }
        }
      }
    }
  }
}
