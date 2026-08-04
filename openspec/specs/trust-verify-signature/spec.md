# trust-verify-signature Specification

## Purpose

The trust-verify-signature plugin verifies the signed JWT manifest that
trust-sign attaches to traffic. In the request direction it checks the inbound
request's signature header before proxying; in the response direction it checks
the upstream response's signature header before the response reaches the
client. Verification resolves the issuer's public keys from the JWKS endpoint
named in the token itself and rejects the exchange with an error status when
the token is missing, malformed, or does not verify.

## Requirements

### Requirement: Direction gating

**ID**: `trust-verify-signature.direction-gating`

The plugin SHALL verify the inbound request only when `config.direction` is `request`, and the upstream response only when `config.direction` is `response`. With `direction` unset the plugin SHALL perform no verification and modify no headers in either direction.

#### Scenario: Direction unset is a no-op

**ID**: `trust-verify-signature.direction-gating.unset-noop`

- **WHEN** the plugin is configured without `direction` and a request without any signature header is proxied
- **THEN** the request and response pass through unmodified; no verification headers are added and no error is returned

### Requirement: Request signature verification

**ID**: `trust-verify-signature.request-verification`

With `direction = request`, the plugin SHALL read the inbound request header named by `config.signature_header_key` and verify it as a JWT manifest per the manifest-check and key-discovery requirements. On success the plugin SHALL set the upstream request header `X-Trust-Verify-Signature-Req` to `OK` and forward the original signature header unchanged. On failure the plugin SHALL reject the request with the error status and a JSON body whose `message` field describes the failure, and nothing is proxied upstream.

#### Scenario: Valid token is verified and marked

**ID**: `trust-verify-signature.request-verification.valid-token-verified`

- **WHEN** the inbound request carries, in the configured signature header, a JWT per the interop contract whose `jwks_uri` claim points to a JWKS endpoint serving the public key matching the token's `kid` and signature
- **THEN** the request is proxied upstream with `X-Trust-Verify-Signature-Req: OK` and the signature header still present with its original value

#### Scenario: Missing signature header is rejected

**ID**: `trust-verify-signature.request-verification.missing-header-401`

- **WHEN** the inbound request has no header named by `config.signature_header_key`
- **THEN** the client receives status 401 with a JSON body whose `message` is `Missing Signature in <signature_header_key>`

#### Scenario: Unparseable token is rejected

**ID**: `trust-verify-signature.request-verification.unparseable-token-401`

- **WHEN** the configured signature header is present but its value is not a parseable JWT
- **THEN** the client receives status 401 with a JSON body whose `message` begins with `Bad token`

### Requirement: Response signature verification

**ID**: `trust-verify-signature.response-verification`

With `direction = response`, the plugin SHALL read the upstream response header named by `config.signature_header_key` and verify it as a JWT manifest per the manifest-check and key-discovery requirements, regardless of the upstream response status code. On success the plugin SHALL add the response header `X-Trust-Verify-Signature-Res: OK` and pass the response (including the signature header) through to the client. On failure the plugin SHALL replace the upstream response: the client receives the error status and a JSON body whose `message` field describes the failure instead of the upstream status and body.

#### Scenario: Valid response token is verified and marked

**ID**: `trust-verify-signature.response-verification.valid-token-verified`

- **WHEN** the upstream response carries, in the configured signature header, a JWT per the interop contract that verifies against the JWKS endpoint named in its `jwks_uri` claim
- **THEN** the client receives the upstream response with `X-Trust-Verify-Signature-Res: OK` added and the signature header still present

#### Scenario: Missing response signature header replaces the response

**ID**: `trust-verify-signature.response-verification.missing-header-401`

- **WHEN** the upstream response has no header named by `config.signature_header_key`
- **THEN** the client receives status 401 with a JSON body whose `message` is `Missing Signature in <signature_header_key>`, and the upstream body is not delivered

### Requirement: Issuer key discovery and signature verification

**ID**: `trust-verify-signature.key-discovery`

The plugin SHALL resolve verification keys from the JWKS endpoint named by the token's own `jwks_uri` payload claim. The endpoint must respond with HTTP 200 and a JSON object containing a `keys` array of JWK objects; the verification key is the entry whose `kid` equals the token header's `kid`. The signature SHALL be verified against that JWK using the algorithm named in the token header's `alg`. Failures reject the exchange with the statuses and `message` values below (in the request direction as a request rejection, in the response direction by replacing the response).

#### Scenario: Missing jwks_uri claim is rejected

**ID**: `trust-verify-signature.key-discovery.missing-jwks-uri-401`

- **WHEN** the token parses but its payload has no `jwks_uri` claim
- **THEN** the client receives status 401 with `message` = `Signature missing 'jwks_uri' claim`

#### Scenario: Unusable JWKS endpoint is rejected

**ID**: `trust-verify-signature.key-discovery.jwks-fetch-failure-403`

- **WHEN** the endpoint named by `jwks_uri` is unreachable, responds with a non-200 status, or returns a body that is not JSON with a `keys` array
- **THEN** the client receives status 403 with `message` = `Unable to get public keys`

#### Scenario: Unknown kid is rejected

**ID**: `trust-verify-signature.key-discovery.unknown-kid-401`

- **WHEN** the JWKS response contains no key whose `kid` equals the token header's `kid`
- **THEN** the client receives status 401 with `message` = `Signature public key not found`

#### Scenario: Malformed JWK is rejected

**ID**: `trust-verify-signature.key-discovery.malformed-jwk-401`

- **WHEN** the JWKS entry matching the token's `kid` is not a usable public key (e.g. missing or garbage key material)
- **THEN** the client receives status 401 with `message` = `Public key format error`

#### Scenario: Signature mismatch is rejected

**ID**: `trust-verify-signature.key-discovery.signature-mismatch-401`

- **WHEN** the JWKS entry matching the token's `kid` is a well-formed public key that does not verify the token's signature
- **THEN** the client receives status 401 with `message` = `Signature public key mismatch`

#### Scenario: The token's own jwks_uri is used for key discovery

**ID**: `trust-verify-signature.key-discovery.jwks-uri-claim-trusted`

- **WHEN** a token's `jwks_uri` claim points to an endpoint serving the public key that matches the token's `kid` and signature (and that endpoint is not configured on this plugin instance)
- **THEN** verification succeeds and the exchange is marked verified

#### Scenario: Fetched keys are shared across issuers

**ID**: `trust-verify-signature.key-discovery.keys-shared-across-issuers`

- **TAG**: quirk — fetched keys are cached under a single key regardless of which jwks_uri they came from, so distinct issuers briefly share a keyset
- **WHEN** a request bearing a token with `jwks_uri` A is verified, and immediately afterwards a second request arrives bearing a token whose `jwks_uri` B serves a matching key for its `kid`, where that `kid` is absent from A's keyset
- **THEN** the second request is rejected with status 401 and `message` = `Signature public key not found`, because it is checked against A's keys

### Requirement: Content-digest manifest check

**ID**: `trust-verify-signature.content-digest-check`

When `config.manifest_type` is `content-digest`, the plugin SHALL require the token payload to contain a `cd` claim before signature verification is attempted, and rejects the exchange when it is absent. When `manifest_type` is `signature-only` or unset, the plugin SHALL perform no manifest-content checks. The comparison of the `cd` claim against the request's `Content-Digest` header is unreachable in practice: the code path taken when `cd` is present fails at runtime.

#### Scenario: signature-only and unset add no manifest checks

**ID**: `trust-verify-signature.content-digest-check.signature-only-or-unset-no-checks`

- **WHEN** `manifest_type` is `signature-only` or unset and an otherwise-valid token is presented without any `cd` claim
- **THEN** verification proceeds and succeeds per the key-discovery requirement

#### Scenario: Missing cd claim is rejected in content-digest mode

**ID**: `trust-verify-signature.content-digest-check.missing-cd-claim-401`

- **TAG**: quirk — the producer contract (trust-sign) defines a `digest` claim, not `cd`, so every token produced per that contract is rejected in this mode
- **WHEN** `manifest_type` is `content-digest` and the presented token parses but has no `cd` payload claim (regardless of signature validity)
- **THEN** the client receives status 401 with `message` = `Signature missing content digest manifest (cd)`, before any key discovery occurs

#### Scenario: Present cd claim causes a runtime failure

**ID**: `trust-verify-signature.content-digest-check.present-cd-claim-500`

- **TAG**: quirk — the comparison calls a PDK function that does not exist in Kong 3.9 (`kong.service.request.get_header`), so the match/mismatch branches can never execute
- **WHEN** `manifest_type` is `content-digest` and the presented token parses and has a `cd` payload claim
- **THEN** the exchange fails with status 500

### Requirement: Configuration schema

**ID**: `trust-verify-signature.configuration-schema`

The plugin SHALL only apply to HTTP(S) traffic and SHALL enforce its config schema:

- `signature_header_key` (string, required, default `"X-Edge-Token"`): name of the header carrying the manifest token
- `direction` (string, optional, one of `request`/`response`)
- `manifest_type` (string, optional, one of `signature-only`/`content-digest`)
- `iss_key_grace_period` (number, optional, default `300`): accepted by the schema but has no observable effect (see Out of scope)

#### Scenario: Canonical valid config accepted

**ID**: `trust-verify-signature.configuration-schema.canonical-valid-config`

- **WHEN** a plugin config sets `signature_header_key` = `X-Edge-Token`, `direction` = `request`, and `manifest_type` = `signature-only`
- **THEN** the configuration is accepted by schema validation

#### Scenario: Enumerated fields enforced

**ID**: `trust-verify-signature.configuration-schema.enumerated-fields`

- **WHEN** a plugin config sets `direction` or `manifest_type` to a value outside its allowed set
- **THEN** the configuration is rejected by schema validation

#### Scenario: signature_header_key defaults to X-Edge-Token

**ID**: `trust-verify-signature.configuration-schema.signature-header-key-defaults-to-x-edge-token`

- **WHEN** the plugin is configured without an explicit `signature_header_key`
- **THEN** the schema applies the default `"X-Edge-Token"`, and verification reads the manifest from the `X-Edge-Token` header

## Interop / shared contract

The trust-sign spec (`openspec/specs/trust-sign/spec.md`) is the **source of
truth** for the wire format this plugin consumes. This plugin depends on the
following subset of that contract:

- **Manifest token**: a JWS compact JWT carried in the header named by `signature_header_key` (default `X-Edge-Token`, matching the producer).
- **Token header fields consumed**: `kid` (selects the verification key from the JWKS) and `alg` (names the verification algorithm).
- **Token payload claims consumed**: `jwks_uri` only (key discovery). The producer's `request_id`, `client_id`, `service_id`, `digest`, `jti`, and `iat` claims are ignored by this plugin.
- The producer contract marks `jwks_uri` as optional (omitted when the producer has no `jwks_uri` configured); this plugin rejects such tokens with 401 per the key-discovery requirement, so producers feeding this verifier must configure `jwks_uri`.
- **Contract mismatch**: this plugin's `content-digest` mode expects a `cd` payload claim, which the producer contract does not define (the producer emits `digest`). See the quirk-tagged scenarios under the content-digest manifest check requirement.
- **JWKS document** (not part of the producer spec; consumed from the endpoint named by `jwks_uri`): HTTP 200, JSON object with a `keys` array of JWK objects each carrying a `kid` and public key material for the token's `alg`.

## Out of scope

- Issuer key refresh via `config.iss_key_grace_period`: the retry/refresh code is unreachable (every branch before it returns), so the field has no observable effect.
- JWK n/e-to-PEM conversion module (`key_conversion`): loaded but never invoked.
- Commented-out gate that would skip response verification for non-200 upstream statuses.
- RFC 9421 HTTP Message Signatures: the plugin catalogue describes this plugin as RFC-9421 verification, but the implementation verifies a JWT manifest header instead.
