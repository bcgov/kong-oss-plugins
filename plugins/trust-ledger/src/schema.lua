local typedefs = require "kong.db.schema.typedefs"

return {
  name = "trust-ledger",
  fields = {
    {protocols = typedefs.protocols_http},
    {
      config = {
        type = "record",
        fields = {
          {endpoint_url = {type = "string"}},
          {provider = {type = "string"}},
          {
            ca_certificates = {
              type = "array",
              elements = {type = "string"},
              required = false,
              default = {}
            }
          }
        }
      }
    }
  }
}
