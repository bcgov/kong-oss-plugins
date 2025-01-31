local typedefs = require "kong.db.schema.typedefs"

local schema = {
  name = "oidc-consumer",
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
              -- description = "The claim that should be used for populating the Consumer username."
            }
          },
          { create_consumer = {
            type = "boolean",
            required = true,
            default = false
            -- description = "Boolean value on whether the consumer record should be created automatically."
          }
        },
      },
      },
    },
  },
}

return schema