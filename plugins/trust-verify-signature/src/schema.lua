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
          },
          {
            manifest_type = {
              type = "string",
              one_of = {
                "signature-only",
                "content-digest"
              }
            }
          },
          {
            iss_key_grace_period = {
              type = "number",
              default = 300
            }
          }
        }
      }
    }
  }
}
