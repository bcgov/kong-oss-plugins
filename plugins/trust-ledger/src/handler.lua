local filter = require("kong.plugins.trust-ledger.ledgers.rekor")
local kong_meta = require "kong.meta"
local kong = kong
local tls = require("resty.kong.tls")
local set_upstream_ssl_trusted_store = tls.set_upstream_ssl_trusted_store
local Queue = require "kong.tools.queue"

local certificate = require "kong.runloop.certificate"
local get_ca_certificate_store = certificate.get_ca_certificate_store

local TrustLedgerHandler = {
  PRIORITY = 600,
  VERSION = kong_meta.version
}

function TrustLedgerHandler:header_filter(conf)
  if kong.response.get_source() ~= "service" then
    return
  end

  if conf.provider == "rekor" then
    local result,
      err = filter.submit_rfc3161_to_rekor(conf.endpoint_url, kong.ctx.shared.rfc3161_artifact)
    if err then
      kong.log.err("Error submitting to Rekor: ", err)
      kong.response.set_header("X-Trust-Ledger-Error", "Failed to submit to Rekor")
      return
    end

    kong.ctx.shared.trust_ledger = {
      provider = conf.provider,
      response = result
    }

    kong.response.set_header("X-Trust-Ledger-Status", result.status)
    kong.response.set_header("X-Trust-Ledger-Uuid", result.ref_id)
  else
    kong.ctx.shared.trust_ledger = {
      provider = conf.provider,
      response = "unsupported ledger provider"
    }

    kong.response.set_header("X-Trust-Ledger-Error", "Unsupported ledger provider")
  end
end

--[[
  Interacts with an immutable ledger service, such as Rekor, to record and verify transparency logs.
  This function typically submits data (e.g., cryptographic signatures, metadata) to the ledger,
  ensuring tamper-evident and auditable records. The ledger is append-only, guaranteeing immutability.
  Common use cases include software supply chain security, artifact attestation, and compliance auditing.
  When calling this function:
    - Ensure data is properly formatted and validated before submission.
    - Handle network errors and verify responses from the ledger service.
    - Use the returned log entry or proof for subsequent verification or auditing processes.
  Reference: https://github.com/sigstore/rekor
]]
function TrustLedgerHandler:log(conf)
  local set_serialize_value = kong.log.set_serialize_value

  if kong.ctx.shared.trust_ledger then
    set_serialize_value("trust_ledger", kong.ctx.shared.trust_ledger)
  end
end

return TrustLedgerHandler
