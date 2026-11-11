# mtls-auth coverage map

> Review aid only — not normative. Clean-room test generation uses spec.md alone.

| Surface | Kind | Disposition |
|---|---|---|
| `config.error_response_code` (integer, optional, default 401, between 400–599) | config | Requirement: Client certificate verification gate; Requirement: Configuration schema |
| `config.upstream_cert_header` (optional) | config | Requirement: Certificate detail headers for upstream |
| `config.upstream_cert_fingerprint_header` (optional) | config | Requirement: Certificate detail headers for upstream |
| `config.upstream_cert_serial_header` (optional) | config | Requirement: Certificate detail headers for upstream |
| `config.upstream_cert_i_dn_header` (optional) | config | Requirement: Certificate detail headers for upstream |
| `config.upstream_cert_s_dn_header` (optional) | config | Requirement: Certificate detail headers for upstream |
| `config.upstream_cert_cn_header` (optional) | config | Requirement: Common Name and Organization headers derived from the subject DN |
| `config.upstream_cert_org_header` (optional) | config | Requirement: Common Name and Organization headers derived from the subject DN |
| `config.upstream_server_name_header` (optional) | config | Requirement: Server Name header derived from SNI |
| `consumer = typedefs.no_consumer` | config | Requirement: Configuration schema |
| `protocols` (restricted to `https` only) | config | Requirement: Configuration schema |
| `entity_checks = {}` (none defined) | config | Requirement: Configuration schema |
| `ngx.var.ssl_client_verify` (gate value) | input | Requirement: Client certificate verification gate |
| `ngx.var.ssl_client_s_dn` (verbatim) | input | Requirement: Certificate detail headers for upstream |
| `ngx.var.ssl_client_raw_cert` (parsed for CN/O via resty.openssl.x509 subject name) | input | Requirement: Common Name and Organization headers derived from the subject DN |
| `ngx.var.ssl_client_escaped_cert` | input | Requirement: Certificate detail headers for upstream |
| `ngx.var.ssl_client_fingerprint` (SHA-1 hex of DER, lowercase, no colons) | input | Requirement: Certificate detail headers for upstream |
| `ngx.var.ssl_client_serial` (hex serial, not decimal) | input | Requirement: Certificate detail headers for upstream |
| `ngx.var.ssl_client_i_dn` | input | Requirement: Certificate detail headers for upstream |
| `ngx.var.ssl_server_name` | input | Requirement: Server Name header derived from SNI |
| Early-exit response (status/body/`Content-Type`) | output | Requirement: Client certificate verification gate |
| Upstream header from `upstream_cert_header` | output | Requirement: Certificate detail headers for upstream |
| Upstream header from `upstream_cert_fingerprint_header` | output | Requirement: Certificate detail headers for upstream |
| Upstream header from `upstream_cert_serial_header` | output | Requirement: Certificate detail headers for upstream |
| Upstream header from `upstream_cert_i_dn_header` | output | Requirement: Certificate detail headers for upstream |
| Upstream header from `upstream_cert_s_dn_header` | output | Requirement: Certificate detail headers for upstream |
| Upstream header from `upstream_cert_cn_header` | output | Requirement: Common Name and Organization headers derived from the subject DN |
| Upstream header from `upstream_cert_org_header` | output | Requirement: Common Name and Organization headers derived from the subject DN |
| Upstream header from `upstream_server_name_header` | output | Requirement: Server Name header derived from SNI |
| `kong.ctx.shared.mtls_auth` table (cert, fingerprint, serial, issuer_dn, subject_dn, common_name, organization) | output | Requirement: Shared certificate context for downstream plugins |
| Missing CN/O → shared-context key absent (nil) | logic | Requirement: Shared certificate context for downstream plugins |
| Overwrite of a client-supplied same-named header | behavior | Requirement: Certificate detail headers for upstream |
| Colliding configured header names last-wins | behavior | Requirement: Certificate detail headers for upstream |
| CN/O from cert subject name (decoded RFC 4514 values, not the escaped DN string) | logic | Requirement: Common Name and Organization headers derived from the subject DN |
| Duplicate CN/O attribute type, last in ASN.1 subject order (not last in reversed RFC 2253 `$ssl_client_s_dn`) | logic | Requirement: Common Name and Organization headers derived from the subject DN |
| Missing target attribute → configured header cleared, client-supplied value discarded | logic | Requirement: Common Name and Organization headers derived from the subject DN |
| Missing SNI → configured server-name header cleared, client-supplied value discarded | logic | Requirement: Server Name header derived from SNI |
