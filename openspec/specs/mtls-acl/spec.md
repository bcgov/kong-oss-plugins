# mtls-acl Specification

## Purpose

The mtls-acl plugin restricts access to a Service or Route based on an
attribute of the verified mTLS client certificate. It runs in the access
phase, reads the attribute value from the shared per-request certificate
context that `mtls-auth` populates (`kong.ctx.shared.mtls_auth` — see
Interop / shared contract), and grants or denies the request according to a
configured allow-list or deny-list of exact values, before proxying
upstream. The plugin never reads the authorization subject from request
content: a client cannot supply, duplicate, or spoof the value it evaluates.

## Requirements

### Requirement: Configuration schema

**ID**: `mtls-acl.configuration-schema`

The plugin SHALL only be configurable for the `https` protocol — it
authorizes mTLS-verified requests, and mTLS requires HTTPS — so schema
validation SHALL reject a `protocols` set containing any other protocol
(`http`, `grpc`, `grpcs`, …). It SHALL NOT be configurable at consumer
scope. Its config schema is:

- `certificate_attribute` (string, required, no default) — which attribute
  of the shared certificate context to evaluate; one of `cert`,
  `fingerprint`, `serial`, `issuer_dn`, `subject_dn`, `common_name`,
  `organization` (the keys of `kong.ctx.shared.mtls_auth`, see Interop /
  shared contract)
- `allow` (array of strings, optional, no default)
- `deny` (array of strings, optional, no default)

The plugin SHALL enforce exactly one of `config.allow` / `config.deny` being
set: both configured at once, neither configured, and either field set to an
explicitly empty array, SHALL each be rejected by schema validation.

#### Scenario: Required field enforced

**ID**: `mtls-acl.configuration-schema.required-field`

- **WHEN** a plugin config omits `certificate_attribute`
- **THEN** the configuration is rejected by schema validation

#### Scenario: Invalid certificate_attribute is rejected

**ID**: `mtls-acl.configuration-schema.invalid-attribute-rejected`

- **WHEN** a plugin config sets `certificate_attribute` to a string outside
  the enumerated attribute list (e.g. `x-client-cert-fp`)
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

- **WHEN** a plugin config sets `certificate_attribute` to one of the
  enumerated attributes and exactly one of `allow` or `deny` to a non-empty
  array of strings
- **THEN** the configuration is accepted by schema validation

#### Scenario: Plugin cannot be scoped to a consumer

**ID**: `mtls-acl.configuration-schema.no-consumer-scope`

- **WHEN** an attempt is made to configure the plugin at consumer scope
- **THEN** the configuration is rejected by schema validation

#### Scenario: Non-https protocol is rejected

**ID**: `mtls-acl.configuration-schema.non-https-protocol-rejected`

- **WHEN** an attempt is made to configure the plugin with a `protocols` set
  containing a protocol other than `https` (e.g. `["http"]`)
- **THEN** the configuration is rejected by schema validation

### Requirement: Certificate attribute extraction

**ID**: `mtls-acl.certificate-attribute-extraction`

The plugin SHALL read the value it authorizes from
`kong.ctx.shared.mtls_auth[config.certificate_attribute]` — the shared
per-request certificate context populated by a trusted preceding plugin,
normally `mtls-auth` (see Interop / shared contract). Request content
(headers, query string, body) SHALL play no part in the decision. When the
shared context entry is absent, when it lacks the configured attribute key,
or when the attribute value is an empty string, the request SHALL be
rejected per the Default deny requirement, regardless of `config.allow` /
`config.deny` contents.

#### Scenario: The configured attribute is the one evaluated

**ID**: `mtls-acl.certificate-attribute-extraction.configured-attribute-selected`

- **WHEN** `mtls-auth` has verified a client certificate on the request,
  `certificate_attribute` is `common_name`, and `config.allow` contains the
  certificate's CN but none of the certificate's other attribute values
- **THEN** the request is proxied to the upstream service

#### Scenario: Attribute missing from the shared context is rejected

**ID**: `mtls-acl.certificate-attribute-extraction.missing-attribute-rejected`

- **WHEN** `mtls-auth` has verified a client certificate on the request,
  `certificate_attribute` is `common_name`, and the certificate's subject DN
  contains no `CN` attribute (so the shared context has no `common_name`
  key)
- **THEN** the client receives status 403 with the Default deny response
  body, and no request reaches the upstream service

#### Scenario: Client request content cannot supply the value

**ID**: `mtls-acl.certificate-attribute-extraction.client-request-cannot-supply-value`

- **WHEN** no preceding plugin has populated `kong.ctx.shared.mtls_auth`,
  and the client's request carries a header whose value exactly matches an
  entry in `config.allow`
- **THEN** the client receives status 403 with the Default deny response
  body, and no request reaches the upstream service

### Requirement: Default deny

**ID**: `mtls-acl.default-deny`

Whenever the plugin does not grant access — because no certificate attribute
value was extracted from the shared context, or (per the Allow-list
evaluation / Deny-list evaluation requirements) the extracted value did not
satisfy the configured list — the plugin SHALL immediately terminate the
request with status `403` and a JSON body `{"message": "You cannot consume
this service"}`; the request SHALL NOT be proxied upstream.

#### Scenario: Missing shared certificate context is rejected

**ID**: `mtls-acl.default-deny.missing-context-rejected`

- **WHEN** a request reaches the plugin and no preceding plugin has
  populated `kong.ctx.shared.mtls_auth` (e.g. `mtls-auth` is not enabled on
  the Service or Route)
- **THEN** the client receives status 403 with a JSON body `{"message": "You
  cannot consume this service"}`, and no request reaches the upstream service

### Requirement: Allow-list evaluation

**ID**: `mtls-acl.allow-list-evaluation`

When `config.allow` is set, the plugin SHALL grant access when the extracted
certificate attribute value is exactly equal (case-sensitive string
equality) to one of the entries in `config.allow`. Otherwise the request is
rejected per the Default deny requirement.

#### Scenario: Attribute value matches an allow-list entry

**ID**: `mtls-acl.allow-list-evaluation.match-grants-access`

- **WHEN** `config.allow` is set and the extracted certificate attribute
  value exactly equals one of its entries
- **THEN** the request is proxied to the upstream service

#### Scenario: Attribute value not in the allow list is rejected

**ID**: `mtls-acl.allow-list-evaluation.no-match-rejected`

- **WHEN** `config.allow` is set and the extracted certificate attribute
  value does not equal any of its entries
- **THEN** the client receives status 403 with the Default deny response body,
  and no request reaches the upstream service

#### Scenario: Case-only mismatch against the allow list is rejected

**ID**: `mtls-acl.allow-list-evaluation.case-only-mismatch-rejected`

- **WHEN** `config.allow` is set to an entry such as `Abc`, and the extracted
  certificate attribute value differs only in letter case (e.g. `abc`)
- **THEN** the client receives status 403 with the Default deny response body,
  and no request reaches the upstream service

### Requirement: Deny-list evaluation

**ID**: `mtls-acl.deny-list-evaluation`

When `config.deny` is set, the plugin SHALL grant access when the extracted
certificate attribute value is NOT exactly equal (case-sensitive string
equality) to any of the entries in `config.deny`. Otherwise the request is
rejected per the Default deny requirement.

#### Scenario: Attribute value not in the deny list is granted access

**ID**: `mtls-acl.deny-list-evaluation.no-match-grants-access`

- **WHEN** `config.deny` is set and the extracted certificate attribute
  value does not equal any of its entries
- **THEN** the request is proxied to the upstream service

#### Scenario: Case-only mismatch against the deny list is granted access

**ID**: `mtls-acl.deny-list-evaluation.case-only-mismatch-grants-access`

- **WHEN** `config.deny` is set to an entry such as `Abc`, and the extracted
  certificate attribute value differs only in letter case (e.g. `abc`)
- **THEN** the request is proxied to the upstream service

#### Scenario: Attribute value in the deny list is rejected

**ID**: `mtls-acl.deny-list-evaluation.match-rejected`

- **WHEN** `config.deny` is set and the extracted certificate attribute
  value exactly equals one of its entries
- **THEN** the client receives status 403 with the Default deny response body,
  and no request reaches the upstream service

## Interop / shared contract

mtls-acl consumes `kong.ctx.shared.mtls_auth`, the shared per-request
certificate context produced by `mtls-auth`. **The `mtls-auth` spec is the
source of truth for this contract**; mtls-acl depends on the following
subset:

- The entry is a table with keys `cert`, `fingerprint`, `serial`,
  `issuer_dn`, `subject_dn`, `common_name`, and `organization` — the values
  `config.certificate_attribute` selects among.
- It is populated only after successful client-certificate verification; a
  key is absent when the certificate lacks the corresponding attribute.
- It lives in per-request Kong worker memory: no client-supplied request
  content can create, alter, or remove it.

For the context to be present, `mtls-auth` must be enabled on the same
Service or Route and run earlier in the access phase (it does: `mtls-auth`
has a higher plugin priority than mtls-acl). When it is not, mtls-acl fails
closed: every request is rejected per the Default deny requirement. Because
the authorization subject travels through `kong.ctx.shared` rather than
request headers, no header-trust precondition is placed on the deployment —
client-supplied headers are simply never consulted.

## Out of scope

- Internal cross-plugin telemetry (`kong.ctx.shared.plugin_results`, written
  via a shared logging helper on every allow/deny decision): not observable
  on the wire and carries no externally visible effect. Distinct from the
  `kong.ctx.shared.mtls_auth` contract, which is normative input to this
  plugin.
