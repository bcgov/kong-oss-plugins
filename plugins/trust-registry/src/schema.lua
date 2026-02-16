local typedefs = require "kong.db.schema.typedefs"

return {
  name = "trust-registry",
  fields = {
    {protocols = typedefs.protocols_http},
    {
      config = {
        type = "record",
        fields = {
          {key_set = {type = "string", required = false, default = nil}}
        }
      }
    }
  }
}
