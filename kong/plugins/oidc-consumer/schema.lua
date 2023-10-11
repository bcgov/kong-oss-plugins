local typedefs = require "kong.db.schema.typedefs"

local schema = {
  name = plugin_name,
  fields = {
    {
      consumer = typedefs.no_consumer
    },
    {
      protocols = typedefs.protocols_http
    },
    { config = {
        type = "record",
        fields = {
          { username_field = {
              type = "string",
              required = true,
              default = "email"
            }
          },
          { create_consumer = {
            type = "boolean",
            required = true,
            default = false
          }
        },
      },
      },
    },
  },
}

return schema