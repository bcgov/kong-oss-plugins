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
            direction = {
              type = "string",
              one_of = {
                "request",
                "response",
              }           
            }
          }
        }
      }
    }
  }
}
