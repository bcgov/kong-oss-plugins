local filter = require("kong.plugins.trust-ledger.ledgers.rekor")
local kong_meta = require "kong.meta"
local kong = kong
local tls = require("resty.kong.tls")
local set_upstream_ssl_trusted_store = tls.set_upstream_ssl_trusted_store

local certificate = require "kong.runloop.certificate"
local get_ca_certificate_store = certificate.get_ca_certificate_store

local TrustLedgerHandler = {
  PRIORITY = 610,
  VERSION = kong_meta.version
}

function TrustLedgerHandler:access(conf)
  kong.log.warn("TrustLedgerHandler:access called")

  -- Set the trusted CA store for this request
  if conf.ca_certificates ~= nil then
    local res,
      err = get_ca_certificate_store(conf.ca_certificates)
    if not res then
      kong.log.err("unable to get upstream TLS CA store, err: ", err)
    end

    local ok,
      err = set_upstream_ssl_trusted_store(res)
    if not ok then
      kong.log.err("Failed to set trusted store: ", err)
    end
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
function TrustLedgerHandler:rewrite(conf)
  if kong.response.get_source() ~= "service" then
    return
  end

  kong.log.warn("Ledger processing")
  local rfc3161_artifact = kong.ctx.shared.rfc3161_artifact
  if not rfc3161_artifact then
    kong.response.set_header("X-Trust-Ledger-Error", "No RFC3161 artifact found")
    return
  end
  if conf.provider == "rekor" then
    local result = filter.submit_rfc3161_to_rekor(conf.endpoint_url, rfc3161_artifact)
    kong.response.set_header("X-Trust-Ledger-Status", result.status)
    kong.response.set_header("X-Trust-Ledger-Body", result.body)
  else
    kong.response.set_header("X-Trust-Ledger-Error", "Unsupported ledger provider")
  end
end

return TrustLedgerHandler
