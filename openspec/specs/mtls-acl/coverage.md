# mtls-acl coverage map

> Review aid only — not normative. Clean-room test generation uses spec.md alone.

| Surface | Kind | Disposition |
|---|---|---|
| `config.certificate_header_name` (`typedefs.header_name`, required) | config | Requirement: Configuration schema; Requirement: Certificate header extraction |
| `config.allow` (array of strings, optional) | config | Requirement: Configuration schema; Requirement: Allow-list evaluation |
| `config.deny` (array of strings, optional) | config | Requirement: Configuration schema; Requirement: Deny-list evaluation |
| `config.hide_certificate_header` (boolean, optional, default false) | config | Requirement: Certificate header hiding on success |
| `consumer = typedefs.no_consumer` | config | Requirement: Configuration schema |
| `protocols = typedefs.protocols_http` | config | Requirement: Configuration schema |
| `entity_checks: only_one_of(config.allow, config.deny)` | config | Requirement: Configuration schema |
| `entity_checks: at_least_one_of(config.allow, config.deny)` | config | Requirement: Configuration schema |
| Request header named by `certificate_header_name` (value) | input | Requirement: Certificate header extraction |
| Request header named by `certificate_header_name` (case of header name) | input | Requirement: Certificate header extraction |
| Request header named by `certificate_header_name` (repeated / multi-valued) | input | Requirement: Certificate header extraction (quirk) |
| Missing / empty-string certificate header | input | Requirement: Default deny |
| `contains()` match semantics (exact, case-sensitive string equality) | logic | Requirement: Allow-list evaluation; Requirement: Deny-list evaluation |
| 403 rejection status/body | output | Requirement: Default deny |
| Upstream proxying (allowed vs denied) | output | Requirement: Allow-list evaluation; Requirement: Deny-list evaluation |
| Removal of `certificate_header_name` header from upstream request | output | Requirement: Certificate header hiding on success |
| `kong.ctx.shared.plugin_results` / `log.exit_with_reason` / `log.continue_with_reason` (internal cross-plugin telemetry) | internal | Out of scope |
