# trust-registry Specification

## Purpose

Publish public keys registered in Kong as a JWKS response from routes using trust-registry. This specification records the existing implementation, including reviewable quirks; it does not adopt either experimental AI implementation.

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
- **TAG**: quirk — An ordinary empty Lua table serializes as an object rather than the JWKS-required array.
- **WHEN** config.key_set names an existing keyset with no keys
- **THEN** the response is status 200 with JSON body {"keys":{}} and Content-Type application/json

#### Scenario: Method is route controlled
**ID**: `trust-registry.keyset-selection.post-request`
- **WHEN** a route permitting POST has this plugin configured for an existing keyset containing a valid key and a POST reaches that route
- **THEN** the plugin returns status 200 and the same JWKS key as a GET request

### Requirement: Stored JWK publication
**ID**: `trust-registry.stored-jwk`

The plugin SHALL publish a stored JWK by decoding its JSON unchanged; stored JWK takes precedence over PEM on a key entity. It does not rewrite its kid from the Kong entity or add use. Stored JWK content is passed through, including any private members if present.

#### Scenario: JWK passes through
**ID**: `trust-registry.stored-jwk.pass-through`
- **WHEN** a selected key contains a public RSA JWK with kid and use="enc"
- **THEN** the published JWK equals the stored JWK, including kid and use="enc"

#### Scenario: Stored private members pass through
**ID**: `trust-registry.stored-jwk.private-members`
- **TAG**: quirk — The baseline does not sanitize stored JWKs; only public JWKs should be registered. Do not treat this as a desired security contract.
- **WHEN** a selected key has a stored JWK containing a private RSA d member
- **THEN** the published JWK retains that d member

### Requirement: PEM publication
**ID**: `trust-registry.pem-publication`

The plugin SHALL convert PEM public keys to JWK using native OpenSSL public JWK serialization, set kid to the Kong key entity kid, and add use="sig". For RSA this includes kty, n and e; for EC it includes kty, crv, x and y. Private PEM material is not exported.

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

The baseline does not normalize database errors or malformed stored JSON into an explicit JSON error response.

#### Scenario: Database keyset lookup failure
**ID**: `trust-registry.failure-behavior.lookup-error`
- **TAG**: quirk — Lookup failure is indistinguishable from a missing keyset.
- **WHEN** keyset lookup returns nil plus a database error for a captured keyset
- **THEN** the plugin returns status 404 and {"message":"Key set not found"}

#### Scenario: Key iteration failure
**ID**: `trust-registry.failure-behavior.iterator-error`
- **TAG**: quirk — There is no explicit 500 response.
- **WHEN** key enumeration yields an error
- **THEN** the access handler returns without producing a JWKS response and request processing continues upstream

#### Scenario: Invalid stored JSON
**ID**: `trust-registry.failure-behavior.invalid-jwk`
- **TAG**: quirk — No protected JSON decode is used.
- **WHEN** a selected key contains syntactically invalid JWK JSON
- **THEN** JSON decoding raises an error rather than skipping that key

## Out of scope

- Runtime fault injection for database lookup/iterator errors and invalid persisted JWK JSON has no exported pure seam; these scenarios remain blocked for clean-room tests. Kong Admin validation can prevent creating these states.
- The malformed-PEM publication scenario may be blocked by Kong Admin validation; the conversion helper still permits testing parsing failure.
- No independent URL matcher, method gate, authentication policy, caching contract, or environment-variable input is implemented by this plugin. Route configuration governs reachability.
- Private stored JWK acceptance depends on Kong entity validation; if rejected by Kong, its publication scenario needs a seam rather than bypassing validation.
- Logging text and internal plugin-log context, DAO pagination mechanics, plugin priority/version, packaging metadata, and serialization-library internals are outside the behavioral contract.
