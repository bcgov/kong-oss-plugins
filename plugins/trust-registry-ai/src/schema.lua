-- schema.lua: trust-registry-ai
-- FR-008: Plugin requires zero configuration parameters.
local typedefs = require "kong.db.schema.typedefs"

return {
  name = "trust-registry-ai",
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
