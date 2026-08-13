# mtls-auth Specification

## Purpose

The mtls-auth plugin authenticates clients using mutual TLS (mTLS). It runs in
the access phase, gating the request on the TLS client-certificate
verification result already computed by Kong/nginx, then exposes details of
the verified client certificate to the upstream service via configurable
request headers. It also always publishes the verified certificate's attributes
to `kong.ctx.shared.mtls_auth`, a per-request shared context that downstream
plugins in the same request (e.g. `mtls-acl`) consume without any exposure to
client-supplied headers.

## Requirements

### Requirement: Client certificate verification gate

**ID**: `mtls-auth.certificate-verification-gate`

The plugin SHALL allow the request to proceed only when the nginx variable `ssl_client_verify` is exactly the string `"SUCCESS"`. Otherwise the plugin SHALL immediately terminate the request with status `config.error_response_code` (default `401`), a JSON body `{"error": "invalid_request", "error_description": "mTLS client not provided or invalid"}`, and header `Content-Type: application/json`; the request SHALL NOT be proxied upstream, none of the headers described in the other requirements SHALL be set, and the shared certificate context (`kong.ctx.shared.mtls_auth`) SHALL NOT be populated.

#### Scenario: Missing client certificate is rejected with the default status

**ID**: `mtls-auth.certificate-verification-gate.missing-certificate`

- **WHEN** a request arrives with no client certificate presented (`ssl_client_verify` is `"NONE"`), and `config.error_response_code` is unset
- **THEN** the client receives status 401 with a JSON body containing `error` = `"invalid_request"` and `error_description` = `"mTLS client not provided or invalid"`, `Content-Type: application/json`, and no request reaches the upstream service

#### Scenario: Failed client certificate verification is rejected with the default status

**ID**: `mtls-auth.certificate-verification-gate.failed-verification`

- **WHEN** a request arrives with a client certificate that failed verification (`ssl_client_verify` is a `"FAILED:…"` value), and `config.error_response_code` is unset
- **THEN** the client receives status 401 with a JSON body containing `error` = `"invalid_request"` and `error_description` = `"mTLS client not provided or invalid"`, `Content-Type: application/json`, and no request reaches the upstream service

#### Scenario: error_response_code overrides the rejection status

**ID**: `mtls-auth.certificate-verification-gate.custom-status`

- **WHEN** a request fails client certificate verification and `config.error_response_code` is set to a non-default value (e.g. `495`)
- **THEN** the client receives that configured status code with the same JSON error body

#### Scenario: Successful verification allows the request to proceed

**ID**: `mtls-auth.certificate-verification-gate.success-passthrough`

- **WHEN** the TLS client-certificate verification result is exactly `"SUCCESS"`
- **THEN** the plugin does not terminate the request or modify the response to the client; the request is proxied to the upstream service, carrying whichever headers the other requirements add

### Requirement: Certificate detail headers for upstream

**ID**: `mtls-auth.certificate-detail-headers`

When the client certificate is successfully verified, the plugin SHALL, for each of the following config fields set to a non-empty string, set a request header of that name on the request to the upstream service, overwriting any header of the same name the client may already have sent:

- `upstream_cert_header` → the client certificate in PEM format, URL-encoded
- `upstream_cert_fingerprint_header` → SHA-1 digest of the DER-encoded client certificate, lowercase hexadecimal with no colons or spaces (nginx `$ssl_client_fingerprint`; 40 hex characters). This is not SHA-256 and not colon-separated OpenSSL fingerprint notation.
- `upstream_cert_serial_header` → the client certificate serial number in hexadecimal with no colons or spaces (nginx `$ssl_client_serial`; the same string `openssl x509 -noout -serial` prints after `serial=`). This is not the decimal integer.
- `upstream_cert_i_dn_header` → the client certificate issuer distinguished name, verbatim
- `upstream_cert_s_dn_header` → the client certificate subject distinguished name, verbatim

When one of these fields is left unset (or set to an empty string), the corresponding header SHALL NOT be added.

Colliding header names are accepted. When two config fields target the same header, the later setter wins. Order: the five fields above, then CN, then Organization, then server name.

#### Scenario: All configured headers carry certificate details

**ID**: `mtls-auth.certificate-detail-headers.all-configured`

- **WHEN** all five fields above are configured with distinct header names and a request with a verified client certificate is proxied
- **THEN** each configured upstream request header carries the corresponding certificate value (PEM/URL-encoded certificate, SHA-1 hex fingerprint, hex serial, issuer DN, subject DN) verbatim

#### Scenario: Colliding configured header names last-wins

**ID**: `mtls-auth.certificate-detail-headers.colliding-names-last-wins`

- **WHEN** `upstream_cert_serial_header` and `upstream_cert_s_dn_header` are both set to the same name (e.g. `X-Client-Cert`) and a request with a verified client certificate is proxied
- **THEN** the upstream request carries that header with the subject DN, not the serial number

#### Scenario: Fingerprint is SHA-1 hex of the DER certificate

**ID**: `mtls-auth.certificate-detail-headers.fingerprint-sha1-hex`

- **WHEN** `upstream_cert_fingerprint_header` is configured and a request with a verified client certificate is proxied
- **THEN** that header equals the SHA-1 digest of the certificate's DER encoding as lowercase hexadecimal with no colons or spaces (40 characters) — not SHA-256, and not colon-separated

#### Scenario: Serial is hexadecimal not decimal

**ID**: `mtls-auth.certificate-detail-headers.serial-hex`

- **WHEN** `upstream_cert_serial_header` is configured and the verified client certificate has a serial whose decimal and hexadecimal forms differ (e.g. serial 10)
- **THEN** that header equals the hexadecimal serial with no colons or spaces (e.g. `0A`), not the decimal form (`10`)

#### Scenario: Unset header options are omitted

**ID**: `mtls-auth.certificate-detail-headers.unset-omitted`

- **WHEN** none of the five fields above are configured and a request with a verified client certificate is proxied
- **THEN** none of the five corresponding headers are present on the upstream request

#### Scenario: Plugin-computed value overwrites a client-supplied header of the same name

**ID**: `mtls-auth.certificate-detail-headers.overwrites-client-header`

- **WHEN** a field above is configured to a header name, and the incoming client request already carries a header with that same name set to an attacker-chosen value
- **THEN** the upstream request carries only the plugin-computed value for that header; the client-supplied value is discarded, not appended

### Requirement: Common Name and Organization headers derived from the subject DN

**ID**: `mtls-auth.subject-dn-derived-headers`

The plugin SHALL take the Common Name (`CN`) and Organization (`O`) from the verified client certificate's subject name. The values SHALL be the decoded attribute values: RFC 4514 string encoding (`\,`, `\+`, hex `\XX`, and other escape pairs) is not part of the value. If the subject contains more than one RDN of the same type, the **last** occurrence's value is the one used.

When `config.upstream_cert_cn_header` is set to a non-empty string, the plugin SHALL set that header on the upstream request to the decoded `CN` value. When `config.upstream_cert_org_header` is set to a non-empty string, the plugin SHALL set that header to the decoded `O` value. Each of these headers, like the others in this plugin, overwrites any header of the same name the client already sent.

When the subject contains no RDN of the target type (`CN` or `O`), the plugin SHALL instead remove the configured header from the request — including any value the client supplied with that same header name — and SHALL continue processing the request normally, still setting every other configured header. The plugin SHALL NOT leave a client-supplied value on that header name intact: omitting the derived value means clearing the header, not skipping the header entirely.

The verbatim subject DN on `upstream_cert_s_dn_header` (and in shared context `subject_dn`) remains the nginx RFC 2253 string and is not decoded.

#### Scenario: CN and Organization extracted from a simple subject DN

**ID**: `mtls-auth.subject-dn-derived-headers.simple-extraction`

- **WHEN** `upstream_cert_cn_header` and `upstream_cert_org_header` are configured, and the verified client certificate's subject DN is `CN=Alice Example,O=Example Org,C=US`
- **THEN** the upstream request's CN header carries `Alice Example` and its Organization header carries `Example Org`

#### Scenario: Escaped comma in an RDN value is decoded

**ID**: `mtls-auth.subject-dn-derived-headers.escaped-comma-decoded`

- **WHEN** `upstream_cert_cn_header` is configured and the verified client certificate's Common Name contains a comma (e.g. `Smith, Jr.`, which nginx's RFC 2253 subject DN encodes as `Smith\, Jr.`)
- **THEN** the CN header carries `Smith, Jr.` without the escape backslash

#### Scenario: Hex-escaped octet in an RDN value is decoded

**ID**: `mtls-auth.subject-dn-derived-headers.hex-escape-decoded`

- **WHEN** `upstream_cert_cn_header` is configured and the verified client certificate's Common Name contains a non-ASCII character that nginx's RFC 2253 subject DN encodes as hex (e.g. CN `Café` appearing in the DN string as `Caf\C3\A9`)
- **THEN** the CN header carries the decoded value `Café`, not the hex-escaped DN form

#### Scenario: Duplicate attribute type keeps the last occurrence

**ID**: `mtls-auth.subject-dn-derived-headers.duplicate-attribute-last-wins`

- **WHEN** `upstream_cert_cn_header` is configured and the subject DN contains two RDNs of type `CN`, e.g. `CN=First,OU=Sales,CN=Second`
- **THEN** the CN header carries `Second`

#### Scenario: Missing CN clears the configured header and the request continues

**ID**: `mtls-auth.subject-dn-derived-headers.cn-missing-header-cleared`

- **WHEN** `upstream_cert_cn_header` is configured, and the verified client certificate's subject DN contains no `CN` RDN
- **THEN** the request is proxied to the upstream service without the `upstream_cert_cn_header` header present — even if the client's original request carried a header with that name — and every other configured header is still set

#### Scenario: Missing Organization clears the configured header and the request continues

**ID**: `mtls-auth.subject-dn-derived-headers.org-missing-header-cleared`

- **WHEN** `upstream_cert_org_header` is configured, and the verified client certificate's subject DN contains no `O` RDN
- **THEN** the request is proxied to the upstream service without the `upstream_cert_org_header` header present — even if the client's original request carried a header with that name — and every other configured header is still set

#### Scenario: Plugin-computed CN overwrites a client-supplied header of the same name

**ID**: `mtls-auth.subject-dn-derived-headers.overwrites-client-cn-header`

- **WHEN** `upstream_cert_cn_header` is configured to a header name, the verified client certificate's subject DN contains a `CN` RDN, and the incoming client request already carries a header with that same name set to an attacker-chosen value
- **THEN** the upstream request carries only the plugin-computed `CN` value for that header; the client-supplied value is discarded, not appended

#### Scenario: Plugin-computed Organization overwrites a client-supplied header of the same name

**ID**: `mtls-auth.subject-dn-derived-headers.overwrites-client-org-header`

- **WHEN** `upstream_cert_org_header` is configured to a header name, the verified client certificate's subject DN contains an `O` RDN, and the incoming client request already carries a header with that same name set to an attacker-chosen value
- **THEN** the upstream request carries only the plugin-computed `O` value for that header; the client-supplied value is discarded, not appended

### Requirement: Server Name header derived from SNI

**ID**: `mtls-auth.server-name-header`

When `config.upstream_server_name_header` is set to a non-empty string, the plugin SHALL set that header on the upstream request to the TLS server name (SNI) the client requested (`ssl_server_name`). Like the other headers this plugin sets, it overwrites any header of the same name the client already sent.

When SNI is absent (the client did not send a server_name in the TLS handshake), the plugin SHALL instead remove the configured header from the request — including any value the client supplied with that same header name — and SHALL continue processing the request normally, still setting every other configured header. The plugin SHALL NOT leave a client-supplied value on that header name intact: omitting the SNI value means clearing the header, not skipping the header entirely.

When `config.upstream_server_name_header` is left unset (or set to an empty string), the plugin SHALL NOT add or remove any SNI header.

#### Scenario: Configured header carries the SNI hostname

**ID**: `mtls-auth.server-name-header.sni-present`

- **WHEN** `upstream_server_name_header` is configured and a request with a verified client certificate presents SNI (e.g. `api.example.gov.bc.ca`)
- **THEN** the upstream request carries that configured header equal to the SNI hostname

#### Scenario: Missing SNI clears the configured header and the request continues

**ID**: `mtls-auth.server-name-header.sni-absent-header-cleared`

- **WHEN** `upstream_server_name_header` is configured, and a request with a verified client certificate does not present SNI
- **THEN** the request is proxied to the upstream service without the `upstream_server_name_header` header present — even if the client's original request carried a header with that name — and every other configured header is still set

#### Scenario: Unset server-name option is omitted

**ID**: `mtls-auth.server-name-header.unset-omitted`

- **WHEN** `upstream_server_name_header` is not configured and a request with a verified client certificate is proxied
- **THEN** the plugin does not add an SNI header to the upstream request

#### Scenario: Plugin-computed SNI overwrites a client-supplied header of the same name

**ID**: `mtls-auth.server-name-header.overwrites-client-header`

- **WHEN** `upstream_server_name_header` is configured to a header name, the verified request presents SNI, and the incoming client request already carries a header with that same name set to an attacker-chosen value
- **THEN** the upstream request carries only the TLS SNI hostname for that header; the client-supplied value is discarded, not appended

### Requirement: Shared certificate context for downstream plugins

**ID**: `mtls-auth.shared-certificate-context`

On every request that passes the certificate-verification gate, and independent of any configuration, the plugin SHALL populate `kong.ctx.shared.mtls_auth` with a table of the verified client certificate's attributes, using exactly these keys:

- `cert` — the client certificate in PEM format, URL-encoded (same value as the `upstream_cert_header` header)
- `fingerprint` — SHA-1 hex of the DER-encoded certificate, same encoding as the `upstream_cert_fingerprint_header` header (nginx `$ssl_client_fingerprint`)
- `serial` — hexadecimal serial, same encoding as the `upstream_cert_serial_header` header (nginx `$ssl_client_serial`)
- `issuer_dn` — the client certificate issuer distinguished name, verbatim
- `subject_dn` — the client certificate subject distinguished name, verbatim
- `common_name` — the decoded `CN` value from the certificate subject, per the Common Name and Organization headers requirement
- `organization` — the decoded `O` value from the certificate subject, per the same requirement

When the subject DN contains no RDN of the target type, the corresponding key (`common_name` or `organization`) SHALL be absent from the table (nil), not present with an empty value. The context entry lives in per-request Kong worker memory: it SHALL be derived only from the verified TLS connection, and no client-supplied request content (headers, query, body) can create, alter, or remove it. Because the table always carries every available attribute, downstream consumers select which attribute to use; this plugin takes no configuration for the shared context.

The observable seam for these scenarios is any plugin that runs later in the same request's access phase and reads `kong.ctx.shared.mtls_auth` (e.g. `mtls-acl`, or a test-only observer plugin that echoes the table).

#### Scenario: Shared context is populated on every verified request

**ID**: `mtls-auth.shared-certificate-context.populated-on-verified-request`

- **WHEN** a request with a verified client certificate is processed, regardless of which (if any) config fields are set
- **THEN** a plugin running later in the same request's access phase observes `kong.ctx.shared.mtls_auth` as a table whose `cert`, `fingerprint`, `serial`, `issuer_dn`, `subject_dn`, `common_name`, and `organization` keys carry the corresponding values of the verified client certificate, with `fingerprint` and `serial` using the SHA-1 hex and hex-serial encodings from the Certificate detail headers requirement

#### Scenario: Missing CN leaves the common_name key absent

**ID**: `mtls-auth.shared-certificate-context.cn-missing-key-absent`

- **WHEN** a request with a verified client certificate whose subject DN contains no `CN` RDN is processed
- **THEN** a plugin running later in the same request's access phase observes `kong.ctx.shared.mtls_auth` with no `common_name` key, while the other keys are still populated

#### Scenario: Missing Organization leaves the organization key absent

**ID**: `mtls-auth.shared-certificate-context.org-missing-key-absent`

- **WHEN** a request with a verified client certificate whose subject DN contains no `O` RDN is processed
- **THEN** a plugin running later in the same request's access phase observes `kong.ctx.shared.mtls_auth` with no `organization` key, while the other keys are still populated

### Requirement: Configuration schema

**ID**: `mtls-auth.configuration-schema`

The plugin SHALL only be configurable for the `https` protocol — mTLS requires HTTPS, so schema validation SHALL reject a `protocols` set containing any other protocol (`http`, `grpc`, `grpcs`, …) — and SHALL NOT be configurable at consumer scope. Its config schema has no required fields, no enumerated (`one_of`) fields, and no cross-field validation rules:

- `error_response_code` (integer, optional, default `401`; schema validation SHALL reject a non-integer and any value outside the inclusive range 400–599)
- `upstream_cert_header` (string, optional, no default)
- `upstream_cert_fingerprint_header` (string, optional, no default)
- `upstream_cert_serial_header` (string, optional, no default)
- `upstream_cert_i_dn_header` (string, optional, no default)
- `upstream_cert_s_dn_header` (string, optional, no default)
- `upstream_cert_cn_header` (string, optional, no default)
- `upstream_cert_org_header` (string, optional, no default)
- `upstream_server_name_header` (string, optional, no default)

#### Scenario: Minimal (empty) config is valid

**ID**: `mtls-auth.configuration-schema.minimal-config-valid`

- **WHEN** a plugin config with no fields set is applied
- **THEN** the configuration is accepted by schema validation, `error_response_code` defaults to `401`, and (per the other requirements) no certificate-detail, CN/Organization, or server-name headers are added on a verified request

#### Scenario: Plugin cannot be scoped to a consumer

**ID**: `mtls-auth.configuration-schema.no-consumer-scope`

- **WHEN** an attempt is made to configure the plugin at consumer scope
- **THEN** the configuration is rejected by schema validation

#### Scenario: Non-https protocol is rejected

**ID**: `mtls-auth.configuration-schema.non-https-protocol-rejected`

- **WHEN** an attempt is made to configure the plugin with a `protocols` set containing a protocol other than `https` (e.g. `["http"]`)
- **THEN** the configuration is rejected by schema validation

#### Scenario: error_response_code below 400 is rejected

**ID**: `mtls-auth.configuration-schema.error-response-code-below-400`

- **WHEN** a plugin config sets `error_response_code` to `399`
- **THEN** the configuration is rejected by schema validation

#### Scenario: error_response_code above 599 is rejected

**ID**: `mtls-auth.configuration-schema.error-response-code-above-599`

- **WHEN** a plugin config sets `error_response_code` to `600`
- **THEN** the configuration is rejected by schema validation

#### Scenario: non-integer error_response_code is rejected

**ID**: `mtls-auth.configuration-schema.error-response-code-must-be-integer`

- **WHEN** a plugin config sets `error_response_code` to a non-integer number (e.g. `401.5`)
- **THEN** the configuration is rejected by schema validation

## Interop / shared contract

`kong.ctx.shared.mtls_auth` is the shared contract between mtls-auth (the
producer) and downstream consumer plugins such as `mtls-acl`. **This spec is
the source of truth for that contract**: a table with the keys `cert`,
`fingerprint`, `serial`, `issuer_dn`, `subject_dn`, `common_name`, and
`organization` (see the Shared certificate context requirement), populated
only after successful client-certificate verification, with a key absent when
the certificate lacks the corresponding attribute. `fingerprint` is SHA-1 hex
of the DER certificate (no colons); `serial` is hexadecimal (not decimal);
both match the corresponding upstream header encodings.

Because `kong.ctx.shared` is per-request memory inside Kong, the contract is
trustworthy by construction: a client cannot supply, duplicate, or spoof it
the way it could a request header. Consumers can therefore treat the absence
of `kong.ctx.shared.mtls_auth` as "no verified client certificate was
established on this request" and fail closed. The configurable upstream
headers remain available for upstream services outside Kong; plugins inside
Kong should consume the shared context instead of headers.
