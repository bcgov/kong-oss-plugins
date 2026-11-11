# trust-registry Specification

## Purpose

Publish public keys registered in Kong as a JWKS response from routes using trust-registry. This specification defines safe public-key publication and explicit failure handling for the existing trust-registry implementation.

## Requirements

### Requirement: Configuration schema
**ID**: `trust-registry.configuration-schema`

The plugin SHALL support HTTP and HTTPS. Its config record contains only `key_set`: optional string, default unset (nil), with no enumerated values or custom validation rules.

#### Scenario: Canonical configuration
**ID**: `trust-registry.configuration-schema.valid-config`
- **WHEN** config is empty
- **THEN** configuration validation succeeds

#### Scenario: Named keyset configuration
**ID**: `trust-registry.configuration-schema.named-config`
- **WHEN** config contains key_set="registry-example"
- **THEN** configuration validation succeeds

### Requirement: Keyset selection
**ID**: `trust-registry.keyset-selection`

The plugin SHALL choose a keyset using the named route URI capture `key_set` first, then config.key_set, and otherwise enumerate all Kong keys. A route must attach this plugin; the plugin does not itself restrict request method or path. Successful responses have status 200, Content-Type application/json, and a JSON object with a keys member.

#### Scenario: All registered keys
**ID**: `trust-registry.keyset-selection.all-keys`
- **WHEN** neither a named key_set URI capture nor config.key_set is present and valid keys exist in two distinct keysets
- **THEN** the response contains keys from both keysets

#### Scenario: Configured keyset
**ID**: `trust-registry.keyset-selection.configured`
- **WHEN** config.key_set names an existing keyset containing a valid key and another keyset contains a different key
- **THEN** the response contains only the configured keyset key

#### Scenario: URI capture overrides configuration
**ID**: `trust-registry.keyset-selection.capture-precedence`
- **WHEN** the named key_set URI capture names one existing keyset and config.key_set names another, each with a different valid key
- **THEN** the response contains only the captured keyset key

#### Scenario: Unknown captured keyset
**ID**: `trust-registry.keyset-selection.missing-capture`
- **WHEN** the named key_set URI capture names an unknown keyset while config.key_set names an existing keyset
- **THEN** the response is status 404 with JSON body {"message":"Key set not found"}; there is no fallback to configured keys

#### Scenario: Unknown configured keyset
**ID**: `trust-registry.keyset-selection.missing-config`
- **WHEN** no named key_set capture is present and config.key_set names an unknown keyset
- **THEN** the response is status 404 with JSON body {"message":"Key set not found"}

#### Scenario: Empty keyset
**ID**: `trust-registry.keyset-selection.empty-set`
- **WHEN** config.key_set names an existing keyset with no keys
- **THEN** the response is status 200 with JSON body {"keys":[]} and Content-Type application/json

#### Scenario: Method is route controlled
**ID**: `trust-registry.keyset-selection.post-request`
- **WHEN** a route permitting POST has this plugin configured for an existing keyset containing a valid key and a POST reaches that route
- **THEN** the plugin returns status 200 and the same JWKS key as a GET request

### Requirement: Stored JWK publication
**ID**: `trust-registry.stored-jwk`

The plugin SHALL publish only public asymmetric JWK members. Stored JWK takes precedence over PEM. Preserve kid, use, alg, key_ops, x5u, x5c, x5t and x5t#S256 metadata and the public parameters RSA(n,e), EC(crv,x,y), or OKP(crv,x). Omit all other members, including private parameters and unknown extensions. Symmetric oct keys and unsupported key types SHALL be omitted. Malformed JSON, non-object JSON, and missing, non-string, or empty required public parameters SHALL be omitted without aborting valid sibling keys. Do not rewrite kid from the Kong entity or add use. Unit tests MAY call `build` (`require "jwks"`) with injected keys/keysets DAOs to exercise persisted invalid data that Kong Admin rejects.

#### Scenario: JWK passes through
**ID**: `trust-registry.stored-jwk.pass-through`
- **WHEN** a selected key contains a public RSA JWK with kid and use="enc"
- **THEN** the published JWK equals the stored JWK, including kid and use="enc"

#### Scenario: Stored private members removed
**ID**: `trust-registry.stored-jwk.private-members`
- **WHEN** a selected key has a stored JWK containing a private RSA d member
- **THEN** the published JWK contains only public RSA parameters and supported metadata, with no d, p, q, dp, dq, qi, oth or unknown members

#### Scenario: Symmetric key omitted
**ID**: `trust-registry.stored-jwk.symmetric-key`
- **WHEN** a selected key contains kty="oct" and a secret k alongside a valid public key
- **THEN** the symmetric key is omitted and the valid public key is published

#### Scenario: Invalid public parameters omitted
**ID**: `trust-registry.stored-jwk.invalid-parameters`
- **WHEN** selected stored JWKs contain non-object JSON, an unsupported kty, or missing required public parameters
- **THEN** each invalid key is omitted without aborting publication of valid sibling keys

### Requirement: PEM publication
**ID**: `trust-registry.pem-publication`

The plugin SHALL convert PEM public keys to JWK using native OpenSSL public JWK serialization, set kid to the Kong key entity kid, and add use="sig". For RSA this includes kty, n and e; for EC it includes kty, crv, x and y. Private PEM material is not exported. Unit tests MAY call `build` (`require "jwks"`) with injected DAOs to exercise malformed PEM rejected by Kong Admin.

#### Scenario: RSA public key
**ID**: `trust-registry.pem-publication.rsa`
- **WHEN** a selected key has an RSA-2048 PEM public key and an entity kid
- **THEN** the response contains its exact RSA public n and e, kty="RSA", the entity kid, use="sig", and no private RSA fields

#### Scenario: EC public key
**ID**: `trust-registry.pem-publication.ec`
- **WHEN** a selected key has a P-256 PEM public key and an entity kid
- **THEN** the response contains its exact EC public x and y, kty="EC", crv="P-256", the entity kid, use="sig", and no d field

#### Scenario: Malformed PEM omitted
**ID**: `trust-registry.pem-publication.conversion-failure`
- **WHEN** a selected key has malformed PEM public_key alongside another selected valid key
- **THEN** the failed key is omitted and the response is status 200 containing the valid key

### Requirement: PEM conversion failures
**ID**: `trust-registry.pem-conversion`

The conversion helper SHALL return nil and a nonempty error when PEM parsing fails. Unit tests MAY call `public_key_to_jwks` (`require "pem_to_jwks"`).

#### Scenario: Invalid PEM
**ID**: `trust-registry.pem-conversion.invalid-pem`
- **WHEN** public_key_to_jwks is called with "not a PEM" and kid="bad"
- **THEN** it returns nil and an error string beginning "Failed to load key: "

### Requirement: Failure behavior
**ID**: `trust-registry.failure-behavior`

The plugin SHALL return status 500 with JSON body {"message":"Internal server error"} and Content-Type application/json on database lookup or iteration failure. Do not return a partial JWKS, fall through to upstream, or disclose database error details. A missing keyset without a database error remains 404. Malformed individual key data SHALL be skipped so valid siblings can be published. Unit tests MAY call `build` (`require "jwks"`) with injected keys/keysets DAOs for deterministic database faults.

#### Scenario: Database keyset lookup failure
**ID**: `trust-registry.failure-behavior.lookup-error`
- **WHEN** keyset lookup returns nil plus a database error for a captured keyset
- **THEN** the plugin returns status 500 with {"message":"Internal server error"}, Content-Type application/json, and no database error details

#### Scenario: Key iteration failure
**ID**: `trust-registry.failure-behavior.iterator-error`
- **WHEN** key enumeration yields an error
- **THEN** the plugin returns status 500 with {"message":"Internal server error"}, Content-Type application/json, no partial keys, and no upstream fall-through

#### Scenario: Invalid stored JSON
**ID**: `trust-registry.failure-behavior.invalid-jwk`
- **WHEN** a selected key contains syntactically invalid JWK JSON
- **THEN** the invalid key is omitted; valid sibling keys are returned with status 200 and Content-Type application/json; if none remain the body is {"keys":[]}

## Out of scope

- Database faults and invalid persisted entities are tested through the injected DAO seam because Kong Admin validation prevents constructing some states.
- The injected DAO seam covers malformed-PEM publication; the conversion helper also tests parsing failure.
- No independent URL matcher, method gate, authentication policy, caching contract, or environment-variable input is implemented by this plugin. Route configuration governs reachability.

- Logging text and internal plugin-log context, DAO pagination mechanics, plugin priority/version, packaging metadata, and serialization-library internals are outside the behavioral contract.
