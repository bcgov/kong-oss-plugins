local typedefs = require "kong.db.schema.typedefs"

return {
  name = "trust-timestamp",
  fields = {
    {protocols = typedefs.protocols_http},
    {
      config = {
        type = "record",
        fields = {

          {endpoint_url = {type = "string"}},
          {policy_oid = {type = "string"}}

        }
      }
    }
  }
}
