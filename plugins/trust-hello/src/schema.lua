local typedefs = require "kong.db.schema.typedefs"

return {
  name = "trust-hello",
  fields = {
    {protocols = typedefs.protocols_http},
    {
      config = {
        type = "record",
        fields = {}
      }
    }
  }
}
