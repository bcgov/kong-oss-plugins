# Feature Specification: JWKS Endpoint

**Feature Branch**: `001-jwks-endpoint`
**Created**: 2026-04-15
**Status**: Draft
**Input**: User description: "As an SDX Edge Server host, I want to publish my Edge Server public keys so that other Edge Servers can validate JWS documents my server creates."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Retrieve All Public Keys (Priority: P1)

An SDX Edge Server host registers public keys in Kong via the Admin
API. A consuming Edge Server requests the well-known JWKS endpoint to
discover all available public keys. The endpoint returns a complete
JWKS document containing every registered key, regardless of which
keyset it belongs to.

**Why this priority**: This is the core value proposition. Without the
ability to retrieve all keys, no JWS validation is possible. This
alone constitutes a deployable MVP.

**Independent Test**: Can be fully tested by registering one or more
keys in Kong and issuing a GET request to the JWKS endpoint. Delivers
a standards-compliant JWKS document that consumers can use immediately.

**Acceptance Scenarios**:

1. **Given** one or more keys are registered in Kong (as JWK or PEM),
   **When** a consumer sends `GET /.well-known/jwks.json`,
   **Then** the response is a JSON object with a `keys` array
   containing a JWK entry for each registered key, with HTTP status
   200 and Content-Type `application/json`.

2. **Given** a key is registered in Kong with PEM format only,
   **When** a consumer sends `GET /.well-known/jwks.json`,
   **Then** the response includes that key converted to JWK format
   with the correct `kid` value preserved.

3. **Given** no keys are registered in Kong,
   **When** a consumer sends `GET /.well-known/jwks.json`,
   **Then** the response is `{"keys": []}` with HTTP status 200.

---

### User Story 2 - Retrieve Keys by Keyset (Priority: P2)

An SDX Edge Server host organizes keys into named keysets (e.g., by
purpose or rotation group). A consuming Edge Server requests the
keyset-scoped JWKS endpoint to retrieve only the keys belonging to a
specific keyset.

**Why this priority**: Keyset filtering allows consumers to narrow
key discovery to a specific trust context, reducing the number of keys
they must evaluate. This builds on US1 and adds organizational value.

**Independent Test**: Can be tested by registering keys in a named
keyset and issuing a GET request to the keyset-scoped endpoint.
Delivers a filtered JWKS containing only the keys from that keyset.

**Acceptance Scenarios**:

1. **Given** a keyset named "signing" exists with two keys,
   **When** a consumer sends
   `GET /keysets/signing/.well-known/jwks.json`,
   **Then** the response contains exactly those two keys in JWK format
   with HTTP status 200.

2. **Given** a keyset named "signing" exists but has no keys,
   **When** a consumer sends
   `GET /keysets/signing/.well-known/jwks.json`,
   **Then** the response is `{"keys": []}` with HTTP status 200.

3. **Given** no keyset named "nonexistent" exists in Kong,
   **When** a consumer sends
   `GET /keysets/nonexistent/.well-known/jwks.json`,
   **Then** the response is HTTP status 404 with a JSON error body.

---

### Edge Cases

- What happens when a key has both JWK and PEM stored? The JWK
  representation is used directly; PEM conversion is skipped.
- What happens when a PEM key cannot be converted to JWK (e.g.,
  unsupported algorithm)? The key is omitted from the JWKS response
  and an error is logged.
- What happens when the keyset path parameter contains URL-encoded
  characters? The parameter is decoded before lookup.
- What happens when a non-GET method is used? Kong's route
  configuration restricts to GET only; other methods receive 405.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Plugin MUST respond to `GET /.well-known/jwks.json`
  with a JWKS document containing all registered keys.
- **FR-002**: Plugin MUST respond to
  `GET /keysets/{key_set}/.well-known/jwks.json` with a JWKS document
  containing only keys belonging to the named keyset.
- **FR-003**: Response body MUST be a valid JSON Web Key Set per
  RFC 7517: a JSON object with a single `keys` member containing an
  array of JWK objects.
- **FR-004**: Response Content-Type MUST be `application/json`.
- **FR-005**: Each JWK object in the response MUST include the `kid`
  field matching the key's identifier in Kong.
- **FR-006**: Keys stored in PEM format MUST be converted to JWK
  format in the response.
- **FR-007**: Keys stored in JWK format MUST be included as-is
  (no re-encoding or modification).
- **FR-008**: Plugin MUST require zero configuration parameters.
- **FR-009**: When a keyset name is provided and the keyset does not
  exist, the plugin MUST return HTTP 404 with a JSON error body.
- **FR-010**: When no keys match the request (empty keyset or no keys
  registered), the plugin MUST return `{"keys": []}` with HTTP 200.
- **FR-011**: Keys that cannot be converted to JWK format MUST be
  omitted from the response and the failure MUST be logged.
- **FR-012**: PEM-to-JWK conversion MUST use
  `resty.openssl.pkey:tostring("public", "JWK")` for all supported
  key types. The plugin MUST NOT hand-roll parameter extraction or
  base64url encoding for individual key types; delegating to OpenSSL
  keeps the conversion path uniform across RSA, EC, and any key type
  OpenSSL exposes in the future (e.g., Ed25519, Ed448).
- **FR-013**: JWK objects derived from PEM keys MUST include
  `"use": "sig"` to advertise that the key is intended for signature
  verification. Keys already stored in JWK format (Kong's `key.jwk`
  column) MUST pass through unmodified except for the `kid` override
  required by FR-005; the plugin MUST NOT inject `use` into these
  pre-serialized JWKs.

### Key Entities

- **Key**: A cryptographic public key registered in Kong. Has a key
  identifier (`kid`), an optional JWK representation, an optional PEM
  representation, and an optional association to a Key Set.
- **Key Set**: A named collection of keys in Kong. Has a name (used
  as the path parameter) and an identifier. A key set contains zero
  or more keys.
- **JWKS Document**: The response payload. A JSON object with a single
  `keys` array containing JWK objects per RFC 7517.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of registered public keys (JWK or PEM format) are
  discoverable via the all-keys JWKS endpoint.
- **SC-002**: Keyset-filtered requests return only keys belonging to
  the specified keyset, with zero false positives or omissions.
- **SC-003**: Response documents pass validation against the RFC 7517
  JWKS schema.
- **SC-004**: A consuming Edge Server can use the returned JWKS to
  successfully verify a JWS signed by the publishing Edge Server.

## Assumptions

- Kong's Admin API is used to register keys and keysets before the
  plugin is invoked. Key registration is out of scope for this plugin.
- The plugin operates in the `access` phase of Kong's request
  lifecycle and short-circuits the request (no upstream proxy).
- Only public keys are stored and served. Private key material is
  never present in Kong's keys entity for this use case.
- The plugin will be deployed on routes matching the two specified
  path patterns. Route creation is an operational concern outside
  this specification.
- PEM-to-JWK conversion supports RSA and EC key types, as these are
  the standard asymmetric key types used in JWS (RFC 7515).
  (With FR-012 delegating to `resty.openssl.pkey:tostring`, any
  additional key types OpenSSL serializes as JWK will be supported
  automatically.)

## Amendments

### 2026-04-20 — Post-implementation refinements

Following the trust-registry vs trust-registry-ai comparison report
(`comparison-report.md`), two requirements were added after the
initial implementation shipped:

- **FR-012** (new): Replace the plugin's hand-rolled parameter
  extraction pipeline in `pem_to_jwk.lua` with a single call to
  `resty.openssl.pkey:tostring("public", "JWK")`. The original
  implementation (~80 lines) manually extracted `n`/`e` for RSA and
  `x`/`y`/`crv` for EC, base64url-encoded each component, and mapped
  OpenSSL curve short names to JWK `crv` values. The replacement
  (~20 lines) delegates the entire JWK serialization to OpenSSL and
  decodes the resulting JSON, then overlays the Kong-side `kid`.
  This collapses the conversion module and adds automatic support
  for every key type OpenSSL serializes as JWK.
- **FR-013** (new): JWKs produced from PEM keys now carry
  `"use": "sig"`. This matches the human reference implementation
  and accurately advertises the intended use of keys served by this
  plugin (signature verification). JWKs that are already stored as
  JWK in Kong are deliberately left alone — the plugin must not
  silently rewrite operator-provided JWK objects.

These amendments do not alter any existing acceptance scenario;
they tighten the conversion path (FR-012) and extend the JWK
metadata produced from PEM input (FR-013).
