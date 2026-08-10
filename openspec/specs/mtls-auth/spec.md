# mtls-auth Specification

## Purpose

The mtls-auth plugin authenticates clients using mutual TLS (mTLS). It runs in
the access phase, gating the request on the TLS client-certificate
verification result already computed by Kong/nginx, then exposes details of
the verified client certificate to the upstream service via configurable
request headers, plus two headers that are always set regardless of
configuration.

## Requirements

### Requirement: Client certificate verification gate

**ID**: `mtls-auth.certificate-verification-gate`

The plugin SHALL allow the request to proceed only when the nginx variable `ssl_client_verify` is exactly the string `"SUCCESS"`. Otherwise the plugin SHALL immediately terminate the request with status `config.error_response_code` (default `401`), a JSON body `{"error": "invalid_request", "error_description": "mTLS client not provided or invalid"}`, and header `Content-Type: application/json`; the request SHALL NOT be proxied upstream and none of the headers described in the other requirements SHALL be set.

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
- `upstream_cert_fingerprint_header` → the client certificate fingerprint
- `upstream_cert_serial_header` → the client certificate serial number
- `upstream_cert_i_dn_header` → the client certificate issuer distinguished name, verbatim
- `upstream_cert_s_dn_header` → the client certificate subject distinguished name, verbatim

When one of these fields is left unset (or set to an empty string), the corresponding header SHALL NOT be added.

#### Scenario: All configured headers carry certificate details

**ID**: `mtls-auth.certificate-detail-headers.all-configured`

- **WHEN** all five fields above are configured with distinct header names and a request with a verified client certificate is proxied
- **THEN** each configured upstream request header carries the corresponding certificate value (PEM/URL-encoded certificate, fingerprint, serial number, issuer DN, subject DN) verbatim

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

The plugin SHALL parse the verified client certificate's subject distinguished name (an RFC 2253-style string of `TYPE=VALUE` relative distinguished names (RDNs) separated by commas) into a map keyed by RDN type. Splitting occurs on any comma that is not immediately preceded by a backslash (so a `\,` sequence inside a value does not split the RDN there); within each RDN, the type is the substring before the first `=` and the value is the remainder up to (but not including) the splitting comma. The value is stored exactly as it appears in the DN string, including any literal backslash-escape characters — the plugin does not unescape them. If the subject DN contains more than one RDN of the same type, the **last** occurrence's value is the one stored.

When `config.upstream_cert_cn_header` is set to a non-empty string, the plugin SHALL set that header on the upstream request to the parsed `CN` value. When `config.upstream_cert_org_header` is set to a non-empty string, the plugin SHALL set that header to the parsed `O` value. Each of these headers, like the others in this plugin, overwrites any header of the same name the client already sent.

#### Scenario: CN and Organization extracted from a simple subject DN

**ID**: `mtls-auth.subject-dn-derived-headers.simple-extraction`

- **WHEN** `upstream_cert_cn_header` and `upstream_cert_org_header` are configured, and the verified client certificate's subject DN is `CN=Alice Example,O=Example Org,C=US`
- **THEN** the upstream request's CN header carries `Alice Example` and its Organization header carries `Example Org`

#### Scenario: Escaped comma within an RDN value is preserved literally

**ID**: `mtls-auth.subject-dn-derived-headers.escaped-comma-preserved`

- **TAG**: quirk — the escape backslash is used only to locate the correct RDN boundary and is never stripped from the stored value, so the header value differs from the human-readable (unescaped) form of the DN
- **WHEN** `upstream_cert_cn_header` is configured and the subject DN contains an RDN whose value has an escaped comma, e.g. `CN=Smith\, Jr.,O=Example Org`
- **THEN** the CN header carries `Smith\, Jr.` including the literal backslash character, not the unescaped `Smith, Jr.`

#### Scenario: Duplicate attribute type keeps the last occurrence

**ID**: `mtls-auth.subject-dn-derived-headers.duplicate-attribute-last-wins`

- **WHEN** `upstream_cert_cn_header` is configured and the subject DN contains two RDNs of type `CN`, e.g. `CN=First,OU=Sales,CN=Second`
- **THEN** the CN header carries `Second`

#### Scenario: Missing target attribute fails the request

**ID**: `mtls-auth.subject-dn-derived-headers.missing-attribute-fails-request`

- **TAG**: quirk — the plugin does not guard against the target RDN being absent; setting a header to a missing value raises an uncaught error instead of skipping the header or failing gracefully
- **WHEN** `upstream_cert_cn_header` (or `upstream_cert_org_header`) is configured, but the verified client certificate's subject DN contains no `CN` (respectively `O`) RDN
- **THEN** the request fails with a 5xx response and no request is proxied upstream

#### Scenario: Plugin-computed CN overwrites a client-supplied header of the same name

**ID**: `mtls-auth.subject-dn-derived-headers.overwrites-client-cn-header`

- **WHEN** `upstream_cert_cn_header` is configured to a header name, the verified client certificate's subject DN contains a `CN` RDN, and the incoming client request already carries a header with that same name set to an attacker-chosen value
- **THEN** the upstream request carries only the plugin-computed `CN` value for that header; the client-supplied value is discarded, not appended

#### Scenario: Plugin-computed Organization overwrites a client-supplied header of the same name

**ID**: `mtls-auth.subject-dn-derived-headers.overwrites-client-org-header`

- **WHEN** `upstream_cert_org_header` is configured to a header name, the verified client certificate's subject DN contains an `O` RDN, and the incoming client request already carries a header with that same name set to an attacker-chosen value
- **THEN** the upstream request carries only the plugin-computed `O` value for that header; the client-supplied value is discarded, not appended

### Requirement: Fixed TLS metadata headers

**ID**: `mtls-auth.fixed-tls-metadata-headers`

Independent of configuration, whenever the client certificate is successfully verified the plugin SHALL always set two request headers on the upstream request: `X-Tls-Server-Name` to the TLS server name (SNI) the client requested, and `X-Tls-Client-Verify` to the certificate verification result (which, having passed the certificate-verification-gate requirement, is always `"SUCCESS"`). These header names are fixed and not configurable, and like the other headers this plugin sets, they overwrite any header of the same name the client already sent.

#### Scenario: Fixed headers are always set on a verified request

**ID**: `mtls-auth.fixed-tls-metadata-headers.always-set`

- **WHEN** a request with a verified client certificate is proxied, regardless of which (if any) of the other config fields are set
- **THEN** the upstream request carries `X-Tls-Server-Name` equal to the SNI hostname used for the TLS connection, and `X-Tls-Client-Verify` equal to `"SUCCESS"`

#### Scenario: X-Tls-Server-Name overwrites a client-supplied header of the same name

**ID**: `mtls-auth.fixed-tls-metadata-headers.overwrites-client-server-name`

- **WHEN** a request with a verified client certificate is proxied, and the incoming client request already carries an `X-Tls-Server-Name` header set to an attacker-chosen value
- **THEN** the upstream request carries only the TLS SNI hostname in `X-Tls-Server-Name`; the client-supplied value is discarded, not appended

#### Scenario: X-Tls-Client-Verify overwrites a client-supplied header of the same name

**ID**: `mtls-auth.fixed-tls-metadata-headers.overwrites-client-client-verify`

- **WHEN** a request with a verified client certificate is proxied, and the incoming client request already carries an `X-Tls-Client-Verify` header set to an attacker-chosen value
- **THEN** the upstream request carries only `"SUCCESS"` in `X-Tls-Client-Verify`; the client-supplied value is discarded, not appended

### Requirement: Configuration schema

**ID**: `mtls-auth.configuration-schema`

The plugin SHALL only apply to HTTP(S) traffic and SHALL NOT be configurable at consumer scope. Its config schema has no required fields, no enumerated (`one_of`) fields, and no cross-field validation rules:

- `error_response_code` (number, optional, default `401`)
- `upstream_cert_header` (string, optional, no default)
- `upstream_cert_fingerprint_header` (string, optional, no default)
- `upstream_cert_serial_header` (string, optional, no default)
- `upstream_cert_i_dn_header` (string, optional, no default)
- `upstream_cert_s_dn_header` (string, optional, no default)
- `upstream_cert_cn_header` (string, optional, no default)
- `upstream_cert_org_header` (string, optional, no default)

#### Scenario: Minimal (empty) config is valid

**ID**: `mtls-auth.configuration-schema.minimal-config-valid`

- **WHEN** a plugin config with no fields set is applied
- **THEN** the configuration is accepted by schema validation, `error_response_code` defaults to `401`, and (per the other requirements) no certificate-detail or CN/Organization headers are added — only the two fixed TLS metadata headers are set on a verified request

#### Scenario: Plugin cannot be scoped to a consumer

**ID**: `mtls-auth.configuration-schema.no-consumer-scope`

- **WHEN** an attempt is made to configure the plugin at consumer scope
- **THEN** the configuration is rejected by schema validation
