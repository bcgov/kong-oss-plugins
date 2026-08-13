# mtls-acl coverage map

> Review aid only — not normative. Clean-room test generation uses spec.md alone.

| Surface | Kind | Disposition |
|---|---|---|
| `config.certificate_attribute` (string, required, one_of: cert, fingerprint, serial, issuer_dn, subject_dn, common_name, organization) | config | Requirement: Configuration schema; Requirement: Certificate attribute extraction |
| `config.allow` (array of strings, optional) | config | Requirement: Configuration schema; Requirement: Allow-list evaluation |
| `config.deny` (array of strings, optional) | config | Requirement: Configuration schema; Requirement: Deny-list evaluation |
| `consumer = typedefs.no_consumer` | config | Requirement: Configuration schema |
| `protocols` (restricted to `https` only) | config | Requirement: Configuration schema |
| `entity_checks: only_one_of(config.allow, config.deny)` | config | Requirement: Configuration schema |
| `entity_checks: at_least_one_of(config.allow, config.deny)` | config | Requirement: Configuration schema |
| `kong.ctx.shared.mtls_auth` (presence, table shape) | input | Requirement: Certificate attribute extraction; Interop / shared contract |
| Plugin placement relative to `mtls-auth` (global / Service / Route) | input | Interop / shared contract; Requirement: Certificate attribute extraction |
| `kong.ctx.shared.mtls_auth[certificate_attribute]` (value; missing key; empty string) | input | Requirement: Certificate attribute extraction |
| Client request content (headers/query/body) | input | Requirement: Certificate attribute extraction (never consulted) |
| `contains()` match semantics (exact, case-sensitive string equality) | logic | Requirement: Allow-list evaluation; Requirement: Deny-list evaluation |
| 403 rejection status/body | output | Requirement: Default deny |
| Upstream proxying (allowed vs denied) | output | Requirement: Allow-list evaluation; Requirement: Deny-list evaluation |
| `kong.ctx.shared.plugin_results` / `log.exit_with_reason` / `log.continue_with_reason` (internal cross-plugin telemetry) | internal | Out of scope |
