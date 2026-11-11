local typedefs = require "kong.db.schema.typedefs"

return {
  name = "trust-kms",
  entity_checks = {
    { custom_entity_check = {
      field_sources = { "config.backend", "config.operation", "config.aws_alias" },
      fn = function(entity)
        local conf = entity.config
        if conf.backend == "aws" and conf.operation == "sign" and
           (not conf.aws_alias or conf.aws_alias == ngx.null or conf.aws_alias == "") then
          return nil, "config.aws_alias is required for AWS signing"
        end
        return true
      end
    } }
  },
  fields = {
    {protocols = typedefs.protocols_http},
    {
      config = {
        type = "record",
        fields = {
          {
            keyset_name = {
              type = "string",
              description = "Kong key set containing the registered public key; required for signing"
            }
          },
          {
            private_key_location = {
              type = "string",
              description = "Local signing key path; KONG_SIGNING_CERT_KEY takes precedence"
            }
          },
          {
            direction = {
              type = "string",
              one_of = {
                "request",
                "response"
              }
            }
          },
          {
            backend = {
              type = "string",
              default = "local",
              one_of = {
                "local",
                "aws"
              }
            }
          },
          {
            operation = {
              type = "string",
              default = "create_key",
              required = true,
              one_of = {
                "create_key",
                "sign",
                "verify"
              }
            }
          },
          {
            aws_alias = {
              type = "string",
              description = "AWS KMS alias name (alias/...) or alias ARN; required for AWS signing",
              custom_validator = function(value)
                if value:match("^alias/[%w/_%-]+$") or value:match("^arn:[^:]+:kms:[^:]+:%d+:alias/[%w/_%-]+$") then
                  return true
                end
                return nil, "must be an AWS KMS alias name (alias/...) or alias ARN"
              end,
              required = false
            }
          },
          {
            signature_algorithm = {
              type = "string",
              default = "ECDSA_SHA_512",
              one_of = {
                "RSASSA_PSS_SHA_256",
                "RSASSA_PSS_SHA_384",
                "RSASSA_PSS_SHA_512",
                "ECDSA_SHA_256",
                "ECDSA_SHA_384",
                "ECDSA_SHA_512"
              }
            }
          },
          {
            signature_header_key = {
              type = "string"
            }
          }
        }
      }
    }
  }
}
