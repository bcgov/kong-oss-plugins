local typedefs = require "kong.db.schema.typedefs"

return {
  name = "token-exchange",
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
