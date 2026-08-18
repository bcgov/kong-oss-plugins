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
            jwks_uri = {
              type = "string"
            }
          },
          {
            keyid = {
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
          -- {
          --   signature_label = {
          --     type = "string",
          --     required = true,
          --     default = "sig1"
          --   }
          -- },
          -- {
          --   signature_input = {
          --     type = "string",
          --     required = true
          --   }
          -- },
          {
            signature_header_key = {
              type = "string",
              required = true,
              default = "X-Edge-Token"
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
          }
        },
        entity_checks = {
          {
            at_least_one_of = {
              "keyid",
              "keyset_name"
            }
          }
        }
      }
    }
  },
  entity_checks = {
    {
      at_least_one_of = {
        "config.keyid",
        "config.keyset_name"
      }
    }
  }
}
