local typedefs = require "kong.db.schema.typedefs"


local PLUGIN_NAME = "openid-authzen"


local schema = {
  name = PLUGIN_NAME,
  fields = {
    -- the 'fields' array is the top-level entry with fields defined by Kong
    { consumer = typedefs.no_consumer },  -- this plugin cannot be configured on a consumer (typical for auth plugins)
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { target_url = {
              type = "string",
              description = "The full HTTP(S) URL to call to",
              default = "https://httpbin.org/anything" } },
          { json_locator = {
              type = "array",
              description = "Provide JSON coordinates, as an array of strings, for finding where the nested 'data' is that you want",
              elements = { type = "string" },
              default = { "headers", "Host" } } },
          { auth_header_name = {
              type = "string",
              description = "If your callout URL needs an auth header, specify its NAME here (like 'Authorization')",
              required = false } },
          { auth_header_value = {
              type = "string",
              description = "If your callout URL needs an auth header, specify its VALUE here (like 'Basic aGkgZXZlcnlvbmUgPDM=')",
              required = false } },
        },
        entity_checks = {
          { mutually_required = { "auth_header_name", "auth_header_value" }},
        },
      },
    },
  },
}

return schema