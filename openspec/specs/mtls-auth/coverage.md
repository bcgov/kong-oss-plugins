# mtls-auth coverage map

> Review aid only — not normative. Clean-room test generation uses spec.md alone.

| Surface | Kind | Disposition |
|---|---|---|
| `config.error_response_code` (number, optional, default 401) | config | Requirement: Client certificate verification gate |
| `config.upstream_cert_header` (optional) | config | Requirement: Certificate detail headers for upstream |
| `config.upstream_cert_fingerprint_header` (optional) | config | Requirement: Certificate detail headers for upstream |
| `config.upstream_cert_serial_header` (optional) | config | Requirement: Certificate detail headers for upstream |
| `config.upstream_cert_i_dn_header` (optional) | config | Requirement: Certificate detail headers for upstream |
| `config.upstream_cert_s_dn_header` (optional) | config | Requirement: Certificate detail headers for upstream |
| `config.upstream_cert_cn_header` (optional) | config | Requirement: Common Name and Organization headers derived from the subject DN |
| `config.upstream_cert_org_header` (optional) | config | Requirement: Common Name and Organization headers derived from the subject DN |
| `consumer = typedefs.no_consumer` | config | Requirement: Configuration schema |
| `protocols = typedefs.protocols_http` | config | Requirement: Configuration schema |
| `entity_checks = {}` (none defined) | config | Requirement: Configuration schema |
| `ngx.var.ssl_client_verify` (gate value) | input | Requirement: Client certificate verification gate |
| `ngx.var.ssl_client_verify` (reused as header value) | input | Requirement: Fixed TLS metadata headers |
| `ngx.var.ssl_client_s_dn` (verbatim) | input | Requirement: Certificate detail headers for upstream |
| `ngx.var.ssl_client_s_dn` (parsed for CN/O) | input | Requirement: Common Name and Organization headers derived from the subject DN |
| `ngx.var.ssl_client_escaped_cert` | input | Requirement: Certificate detail headers for upstream |
| `ngx.var.ssl_client_fingerprint` | input | Requirement: Certificate detail headers for upstream |
| `ngx.var.ssl_client_serial` | input | Requirement: Certificate detail headers for upstream |
| `ngx.var.ssl_client_i_dn` | input | Requirement: Certificate detail headers for upstream |
| `ngx.var.ssl_server_name` | input | Requirement: Fixed TLS metadata headers |
| Early-exit response (status/body/`Content-Type`) | output | Requirement: Client certificate verification gate |
| Upstream header from `upstream_cert_header` | output | Requirement: Certificate detail headers for upstream |
| Upstream header from `upstream_cert_fingerprint_header` | output | Requirement: Certificate detail headers for upstream |
| Upstream header from `upstream_cert_serial_header` | output | Requirement: Certificate detail headers for upstream |
| Upstream header from `upstream_cert_i_dn_header` | output | Requirement: Certificate detail headers for upstream |
| Upstream header from `upstream_cert_s_dn_header` | output | Requirement: Certificate detail headers for upstream |
| Upstream header from `upstream_cert_cn_header` | output | Requirement: Common Name and Organization headers derived from the subject DN |
| Upstream header from `upstream_cert_org_header` | output | Requirement: Common Name and Organization headers derived from the subject DN |
| `X-Tls-Server-Name` upstream header (fixed) | output | Requirement: Fixed TLS metadata headers |
| `X-Tls-Client-Verify` upstream header (fixed) | output | Requirement: Fixed TLS metadata headers |
| Overwrite of a client-supplied same-named header | behavior | Requirement: Certificate detail headers for upstream |
| DN parsing: split on unescaped commas | logic | Requirement: Common Name and Organization headers derived from the subject DN |
| DN parsing: escaped comma retains literal backslash | logic | Requirement: Common Name and Organization headers derived from the subject DN (quirk) |
| DN parsing: duplicate attribute type, last wins | logic | Requirement: Common Name and Organization headers derived from the subject DN |
| DN parsing: missing target attribute → configured header cleared, client-supplied value discarded | logic | Requirement: Common Name and Organization headers derived from the subject DN |
| `X-Tls-Client-Verify` truthiness check (`if ngx.var.ssl_client_verify then`) | logic | Requirement: Fixed TLS metadata headers (always true once past the verification gate; no separate scenario needed) |
