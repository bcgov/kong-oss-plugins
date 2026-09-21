local typedefs = require "kong.db.schema.typedefs"

return {
    name = "mtls-acl",
    fields = {
        { consumer = typedefs.no_consumer },
        -- mTLS requires HTTPS, so only the https protocol is supported
        { protocols = typedefs.protocols { default = { "https" }, elements = { type = "string", one_of = { "https" } } } },
        {
            config = {
                type = "record",
                fields = {
                    { allow = { type = "array", required = false, elements = { type = "string" } } },
                    { deny = { type = "array", required = false, elements = { type = "string" } } },
                    {
                        -- key of kong.ctx.shared.mtls_auth to match against allow/deny
                        certificate_attribute = {
                            type = "string",
                            required = true,
                            one_of = {
                                "cert",
                                "fingerprint",
                                "serial",
                                "issuer_dn",
                                "subject_dn",
                                "common_name",
                                "organization",
                            },
                        },
                    },
                },
            },
        },
    },
    entity_checks = {
        { only_one_of = { "config.allow", "config.deny" }, },
        { at_least_one_of = { "config.allow", "config.deny" }, },
    },
}
