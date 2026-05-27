local typedefs = require "kong.db.schema.typedefs"

return {
  name = "trust-registry-ai-openspec",
  fields = {
    { protocols = typedefs.protocols_http },
    {
      config = {
        type = "record",
        fields = {}
      }
    }
  }
}
