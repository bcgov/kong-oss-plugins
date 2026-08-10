# mtls-acl Specification

## Purpose

The mtls-acl plugin restricts access to a Service or Route based on a
certificate-derived value carried in a configurable HTTP request header. It
runs in the access phase and grants or denies the request according to a
configured allow-list or deny-list of exact values, before proxying upstream.
The plugin is agnostic to what populates that header: in practice it is
typically deployed alongside `mtls-auth`, which writes one of the client
certificate's attributes (fingerprint, serial, subject DN, CN, etc.) into a
request header that this plugin then reads by name.

## Requirements

### Requirement: Configuration schema

**ID**: `mtls-acl.configuration-schema`

The plugin SHALL only apply to HTTP(S) traffic and SHALL NOT be configurable
at consumer scope. Its config schema is:

- `certificate_header_name` (HTTP header name via `typedefs.header_name`,
  required, no default)
- `allow` (array of strings, optional, no default)
- `deny` (array of strings, optional, no default)
- `hide_certificate_header` (boolean, optional, default `false`)

The plugin SHALL enforce exactly one of `config.allow` / `config.deny` being
set: both configured at once, neither configured, and either field set to an
explicitly empty array, SHALL each be rejected by schema validation. An
invalid HTTP header name for `certificate_header_name` SHALL also be rejected.

#### Scenario: Required field enforced

**ID**: `mtls-acl.configuration-schema.required-field`

- **WHEN** a plugin config omits `certificate_header_name`
- **THEN** the configuration is rejected by schema validation

#### Scenario: Invalid certificate_header_name is rejected

**ID**: `mtls-acl.configuration-schema.invalid-header-name-rejected`

- **WHEN** a plugin config sets `certificate_header_name` to a string that is
  not a valid HTTP header name
- **THEN** the configuration is rejected by schema validation

#### Scenario: Configuring both allow and deny is rejected

**ID**: `mtls-acl.configuration-schema.both-allow-and-deny-rejected`

- **WHEN** a plugin config sets both `allow` and `deny`
- **THEN** the configuration is rejected by schema validation

#### Scenario: Configuring neither allow nor deny is rejected

**ID**: `mtls-acl.configuration-schema.neither-allow-nor-deny-rejected`

- **WHEN** a plugin config sets neither `allow` nor `deny`
- **THEN** the configuration is rejected by schema validation

#### Scenario: Explicitly empty allow array is rejected

**ID**: `mtls-acl.configuration-schema.empty-allow-rejected`

- **WHEN** a plugin config sets `allow` to an empty array and does not set
  `deny`
- **THEN** the configuration is rejected by schema validation

#### Scenario: Explicitly empty deny array is rejected

**ID**: `mtls-acl.configuration-schema.empty-deny-rejected`

- **WHEN** a plugin config sets `deny` to an empty array and does not set
  `allow`
- **THEN** the configuration is rejected by schema validation

#### Scenario: Canonical valid config is accepted

**ID**: `mtls-acl.configuration-schema.canonical-config-valid`

- **WHEN** a plugin config sets `certificate_header_name` and exactly one of
  `allow` or `deny` to a non-empty array of strings
- **THEN** the configuration is accepted by schema validation, and
  `hide_certificate_header` defaults to `false`

#### Scenario: Plugin cannot be scoped to a consumer

**ID**: `mtls-acl.configuration-schema.no-consumer-scope`

- **WHEN** an attempt is made to configure the plugin at consumer scope
- **THEN** the configuration is rejected by schema validation

### Requirement: Certificate header extraction

**ID**: `mtls-acl.certificate-header-extraction`

The plugin SHALL read the certificate value from the incoming request header
named by `config.certificate_header_name`, matching the header name
case-insensitively regardless of the letter case used by the client. A
request that does not carry this header, or carries it with an empty-string
value, SHALL be treated identically to a request with no allow/deny match:
rejected per the Default deny requirement. A request that carries this
header more than once SHALL be rejected per the Default deny requirement,
regardless of whether the individual repeated values would otherwise satisfy
`config.allow` or `config.deny`.

#### Scenario: Header name matched case-insensitively

**ID**: `mtls-acl.certificate-header-extraction.case-insensitive-match`

- **WHEN** `certificate_header_name` is configured as `X-Client-Cert-Fp` and
  the client's request carries a header named `x-client-cert-fp` (different
  letter case) whose value matches an entry in `config.allow`
- **THEN** the plugin extracts the header value and grants access

#### Scenario: Header sent more than once is rejected

**ID**: `mtls-acl.certificate-header-extraction.duplicate-header-rejected`

- **WHEN** the client's request carries the header named by
  `certificate_header_name` more than once, regardless of whether the
  individual repeated values would match an entry in `config.allow` or
  `config.deny`
- **THEN** the client receives status 403 with the Default deny response
  body, and no request reaches the upstream service

### Requirement: Default deny

**ID**: `mtls-acl.default-deny`

Whenever the plugin does not grant access — because no certificate value was
extracted, or (per the Allow-list evaluation / Deny-list evaluation
requirements) the extracted value did not satisfy the configured list — the
plugin SHALL immediately terminate the request with status `403` and a JSON
body `{"message": "You cannot consume this service"}`; the request SHALL NOT
be proxied upstream.

#### Scenario: Missing or empty certificate header is rejected

**ID**: `mtls-acl.default-deny.missing-or-empty-header-rejected`

- **WHEN** a request either does not carry the header named by
  `certificate_header_name`, or carries it with an empty-string value
- **THEN** the client receives status 403 with a JSON body `{"message": "You
  cannot consume this service"}`, and no request reaches the upstream service

### Requirement: Allow-list evaluation

**ID**: `mtls-acl.allow-list-evaluation`

When `config.allow` is set, the plugin SHALL grant access when the extracted
certificate value is exactly equal (case-sensitive string equality) to one of
the entries in `config.allow`. Otherwise the request is rejected per the
Default deny requirement.

#### Scenario: Certificate value matches an allow-list entry

**ID**: `mtls-acl.allow-list-evaluation.match-grants-access`

- **WHEN** `config.allow` is set and the extracted certificate value exactly
  equals one of its entries
- **THEN** the request is proxied to the upstream service

#### Scenario: Certificate value not in the allow list is rejected

**ID**: `mtls-acl.allow-list-evaluation.no-match-rejected`

- **WHEN** `config.allow` is set and the extracted certificate value does not
  equal any of its entries
- **THEN** the client receives status 403 with the Default deny response body,
  and no request reaches the upstream service

#### Scenario: Case-only mismatch against the allow list is rejected

**ID**: `mtls-acl.allow-list-evaluation.case-only-mismatch-rejected`

- **WHEN** `config.allow` is set to an entry such as `Abc`, and the extracted
  certificate value differs only in letter case (e.g. `abc`)
- **THEN** the client receives status 403 with the Default deny response body,
  and no request reaches the upstream service

### Requirement: Deny-list evaluation

**ID**: `mtls-acl.deny-list-evaluation`

When `config.deny` is set, the plugin SHALL grant access when the extracted
certificate value is NOT exactly equal (case-sensitive string equality) to
any of the entries in `config.deny`. Otherwise the request is rejected per
the Default deny requirement.

#### Scenario: Certificate value not in the deny list is granted access

**ID**: `mtls-acl.deny-list-evaluation.no-match-grants-access`

- **WHEN** `config.deny` is set and the extracted certificate value does not
  equal any of its entries
- **THEN** the request is proxied to the upstream service

#### Scenario: Case-only mismatch against the deny list is granted access

**ID**: `mtls-acl.deny-list-evaluation.case-only-mismatch-grants-access`

- **WHEN** `config.deny` is set to an entry such as `Abc`, and the extracted
  certificate value differs only in letter case (e.g. `abc`)
- **THEN** the request is proxied to the upstream service

#### Scenario: Certificate value in the deny list is rejected

**ID**: `mtls-acl.deny-list-evaluation.match-rejected`

- **WHEN** `config.deny` is set and the extracted certificate value exactly
  equals one of its entries
- **THEN** the client receives status 403 with the Default deny response body,
  and no request reaches the upstream service

### Requirement: Certificate header hiding on success

**ID**: `mtls-acl.certificate-header-hiding`

When `config.hide_certificate_header` is `true`, the plugin SHALL remove the
header named by `config.certificate_header_name` from the request before it
is proxied to the upstream service, whenever access is granted (whether by
the Allow-list evaluation or Deny-list evaluation requirement). When
`hide_certificate_header` is `false` (the default), or when the request is
rejected, the plugin SHALL NOT remove the header.

#### Scenario: Header removed after an allow-list match

**ID**: `mtls-acl.certificate-header-hiding.removed-after-allow-match`

- **WHEN** `hide_certificate_header` is `true`, `config.allow` is set, and the
  extracted certificate value matches an allow-list entry
- **THEN** the upstream request does not carry the
  `certificate_header_name` header

#### Scenario: Header removed after a deny-list non-match

**ID**: `mtls-acl.certificate-header-hiding.removed-after-deny-non-match`

- **WHEN** `hide_certificate_header` is `true`, `config.deny` is set, and the
  extracted certificate value does not match any deny-list entry
- **THEN** the upstream request does not carry the
  `certificate_header_name` header

#### Scenario: Header left intact when hide_certificate_header is unset

**ID**: `mtls-acl.certificate-header-hiding.default-leaves-header-intact`

- **WHEN** `hide_certificate_header` is left unset (default `false`) and
  access is granted
- **THEN** the upstream request still carries the
  `certificate_header_name` header with the client-supplied value

## Interop / shared contract

mtls-acl places no requirements on the structure or origin of the header
value it reads — it treats `config.certificate_header_name` as an opaque
string and compares it verbatim against `config.allow`/`config.deny`, without
verifying who set it. This means mtls-acl provides no security guarantee on
its own: if a request can reach mtls-acl with an untrusted, client-supplied
value in the configured header, that value is evaluated exactly like a
value derived from a verified certificate. mtls-acl's access control is
only meaningful when a trusted preceding component in the plugin chain
(typically `mtls-auth`, running at a higher priority) authoritatively sets
or clears the configured header on every request that reaches mtls-acl —
overwriting any client-supplied value when it has one to assert, and
removing the header entirely when it does not. A preceding component that
merely skips setting the header when it has no value to assert (leaving
whatever the client sent intact) does not satisfy this precondition, and
reintroduces client control over the ACL decision.

In deployments that also enable `mtls-auth`, operators typically point
`certificate_header_name` at one of the headers `mtls-auth` populates (e.g.
its fingerprint, serial, subject-DN, CN, or Organization header — see the
`mtls-auth` spec's Certificate detail headers / Common Name and Organization
headers requirements), and populate `allow`/`deny` with the corresponding
certificate values. `mtls-auth`'s Common Name and Organization headers are
a notable case to verify against this precondition: when the subject DN
lacks the target attribute, `mtls-auth` must clear the configured header
rather than leave it untouched, or a client-supplied value for that same
header name would survive to mtls-acl unmodified.

## Out of scope

- Internal cross-plugin telemetry (`kong.ctx.shared.plugin_results`, written
  via a shared logging helper on every allow/deny decision): not observable
  on the wire and carries no externally visible effect.
