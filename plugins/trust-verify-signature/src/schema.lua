local typedefs = require "kong.db.schema.typedefs"

return {
  name = "trust-verify-signature",
  fields = {
    {protocols = typedefs.protocols_http},
    {
      config = {
        type = "record",
        fields = {
          {
            jwks_endpoint = {
              type = "string"
            }
          },
          {
            signature_header_key = {
              type = "string"
            }
          },
          {
            direction = {
              type = "string",
              one_of = {
                "request",
                "response"
              }
            }
          }
        }
      }
    }
  }
}
