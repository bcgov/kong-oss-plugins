local typedefs = require "kong.db.schema.typedefs"

return {
    name = "mtls-auth",
    fields = {
        { consumer = typedefs.no_consumer },
        -- mTLS requires HTTPS, so only the https protocol is supported
        { protocols = typedefs.protocols { default = { "https" }, elements = { type = "string", one_of = { "https" } } } },
        {
            config = {
                type = "record",
                fields = {
                    {
                        error_response_code = {
                            type = "integer",
                            required = false,
                            default = 401,
                            between = {400, 599},
                        },
                    },
                    {
                        upstream_cert_header = {
                            type = "string",
                            required = false,
                        },
                    },
                    {
                        upstream_cert_fingerprint_header = {
                            type = "string",
                            required = false,
                        },
                    },
                    {
                        upstream_cert_serial_header = {
                            type = "string",
                            required = false,
                        },
                    },
                    {
                        upstream_cert_i_dn_header = {
                            type = "string",
                            required = false,
                        },
                    },
                    {
                        upstream_cert_s_dn_header = {
                            type = "string",
                            required = false,
                        },
                    },
                    {
                        upstream_cert_cn_header = {
                            type = "string",
                            required = false,
                        },
                    },
                    {
                        upstream_cert_org_header = {
                            type = "string",
                            required = false,
                        },
                    },
                },
            },
        },
    },
    entity_checks = {},
}
