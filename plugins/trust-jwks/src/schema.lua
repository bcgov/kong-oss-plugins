local typedefs = require "kong.db.schema.typedefs"

return {
  name = "trust-hello",
  fields = {
    {protocols = typedefs.protocols_http},
    {
      config = {
        type = "record",
        fields = {
          -- TLS validation options
          {
            verify_tls = {
              type = "boolean",
              default = true,
              description = "Verify TLS certificate chain"
            }
          },
          {
            require_ev = {
              type = "boolean",
              default = false,
              description = "Require Extended Validation (EV) certificate"
            }
          },
          -- Timeout settings
          {
            connect_timeout = {
              type = "number",
              default = 10000,
              description = "Connection timeout in milliseconds"
            }
          },
          {
            read_timeout = {
              type = "number",
              default = 10000,
              description = "Read timeout in milliseconds"
            }
          },
          -- Header options
          {
            add_cert_info = {
              type = "boolean",
              default = false,
              description = "Add X-Cert-Info header with all known certificate information"
            }
          }
        }
      }
    }
  }
}
