# trust-sign Specification

## Purpose

The trust-sign plugin attests to the integrity of traffic passing through Kong
by attaching a signed JWT "manifest" to either the upstream request or the
downstream response, depending on configuration. In the request direction it
computes a body digest, gathers identity from service tags, and signs a manifest
header for the upstream. In the response direction, it digests the upstream
response body into the `Content-Digest` header (when applicable), and signs a
manifest that echoes claims (including `digest`) from the inbound request token.

## Requirements

### Requirement: Direction gating

**ID**: `trust-sign.direction-gating`

The plugin SHALL act on the request only when `config.direction` is `request`, and on the response only when `config.direction` is `response`. With `direction` unset the plugin SHALL modify no headers in either direction.

#### Scenario: Direction unset is a no-op

**ID**: `trust-sign.direction-gating.unset-noop`

- **WHEN** the plugin is configured without `direction` and a request is proxied
- **THEN** no request or response headers are added, removed, or modified by the plugin

#### Scenario: Request direction leaves the response untouched

**ID**: `trust-sign.direction-gating.request-leaves-response-untouched`

- **WHEN** `direction` is `request` and a request is proxied
- **THEN** the signature and digest headers are added to the upstream request only; the client response is not modified by the plugin

#### Scenario: Response direction leaves the request untouched

**ID**: `trust-sign.direction-gating.response-leaves-request-untouched`

- **WHEN** `direction` is `response` and a request is proxied
- **THEN** the signature and digest headers are added to the client response only; the upstream request is not modified by the plugin

### Requirement: Request digest generation

**ID**: `trust-sign.request-digest-generation`

With `direction = request`, when the incoming request has no `Content-Digest` header, the plugin SHALL compute the SHA-256 digest of the raw request body and set the `Content-Digest` request header to `sha-256=:<base64 digest>:` (standard base64 of the raw digest bytes) before proxying upstream.

#### Scenario: Missing Content-Digest with a non-empty body

**ID**: `trust-sign.request-digest-generation.missing-digest-nonempty-body`

- **WHEN** a request with a non-empty body and no `Content-Digest` header is proxied
- **THEN** the upstream request carries `Content-Digest: sha-256=:<base64(SHA-256(body))>:` and the same value appears in the manifest `digest` claim

#### Scenario: Missing Content-Digest with an empty-string body

**ID**: `trust-sign.request-digest-generation.missing-digest-empty-string-body`

- **WHEN** a request whose raw body is an empty string and has no `Content-Digest` header is proxied
- **THEN** the upstream request carries `Content-Digest` set to the SHA-256 digest of the empty string, and the manifest `digest` claim matches it

#### Scenario: No request body available

**ID**: `trust-sign.request-digest-generation.no-body-available`

- **WHEN** a request with no body at all (raw body unavailable) and no `Content-Digest` header is proxied
- **THEN** no `Content-Digest` header is added and the manifest omits the `digest` claim

#### Scenario: Client-supplied Content-Digest is trusted as-is

**ID**: `trust-sign.request-digest-generation.client-supplied-digest-trusted`

- **TAG**: quirk — the inbound digest is never validated against the actual body, so a client can assert any digest value
- **WHEN** the incoming request already has a `Content-Digest` header, regardless of whether it matches the body
- **THEN** the header is passed through unchanged and its value is copied verbatim into the manifest `digest` claim

### Requirement: Request manifest signing

**ID**: `trust-sign.request-manifest-signing`

With `direction = request`, the plugin SHALL set the request header named by `config.signature_header_key` to a signed JWT whose payload contains the claims `request_id` (the Kong request ID), `client_id` and `service_id` (from service tags), `digest` (the `Content-Digest` value, when available), and `jwks_uri` (from `config.jwks_uri`), plus the standard claims defined in the JWT token format requirement.

#### Scenario: Standard request signing

**ID**: `trust-sign.request-manifest-signing.standard-request-signing`

- **WHEN** `direction` is `request` and a request is proxied to a service tagged `client:c1` and `service:s1`
- **THEN** the upstream request carries the configured signature header containing a JWT with claims `request_id` = the Kong request ID, `client_id` = `"c1"`, `service_id` = `"s1"`, `digest` = the `Content-Digest` value, and `jwks_uri` = the configured value

#### Scenario: Missing service tags yield empty identity claims

**ID**: `trust-sign.request-manifest-signing.missing-service-tags-empty-identity`

- **WHEN** the matched service has no `client:` or `service:` tags (or there is no service)
- **THEN** the manifest claims `client_id` and `service_id` are empty strings

#### Scenario: jwks_uri unset omits the claim

**ID**: `trust-sign.request-manifest-signing.jwks-uri-unset-omits-claim`

- **WHEN** `config.jwks_uri` is not set
- **THEN** the manifest contains no `jwks_uri` claim

#### Scenario: signature_header_key defaults to X-Edge-Token

**ID**: `trust-sign.request-manifest-signing.signature-header-key-defaults-to-x-edge-token`

- **WHEN** the plugin is configured without an explicit `signature_header_key`
- **THEN** the schema applies the default `"X-Edge-Token"`, and signed manifests are written to the `X-Edge-Token` header

### Requirement: JWT token format

**ID**: `trust-sign.jwt-token-format`

Every manifest token the plugin emits SHALL be a JWS compact serialization (three base64url-encoded segments): a JSON header containing `alg` (from `config.alg`) and `kid` (from `config.keyid`); a JSON payload containing the manifest claims plus `jti` (a fresh UUID per token) and `iat` (issue time, Unix seconds); and a signature over `<header>.<payload>` produced with the resolved private key using the digest named by `config.hash_alg` (ECDSA signatures use raw r||s form).

#### Scenario: Token structure

**ID**: `trust-sign.jwt-token-format.token-structure`

- **WHEN** any manifest token is emitted
- **THEN** it has three base64url segments; the decoded header contains `alg` and `kid` matching config; the decoded payload contains a UUID `jti` and numeric `iat`; and the signature verifies against the signing key using the configured `hash_alg`

#### Scenario: Header alg is independent of the actual signing algorithm

**ID**: `trust-sign.jwt-token-format.header-alg-independent-of-signing`

- **TAG**: quirk — `alg` is copied verbatim from config and never reconciled with `hash_alg` or the key type, so the header can misstate the real algorithm (e.g. `alg = RS256` with `hash_alg = sha512`), and an unset `alg` yields a JWS header with no `alg` field
- **WHEN** `config.alg` and `config.hash_alg` name inconsistent algorithms, or `alg` is unset
- **THEN** the token header reports `config.alg` as-is (or omits `alg` entirely) while the signature is actually produced with `config.hash_alg`

### Requirement: Private key resolution

**ID**: `trust-sign.private-key-resolution`

The plugin SHALL sign with the private key read from the file at `config.private_key_location`, unless the environment variable `KONG_SIGNING_CERT_KEY` is set in the Kong process, in which case the key SHALL be read from that path instead for all instances of the plugin. Unit tests MAY call `get_private_key_location` (`require "sign"`).

#### Scenario: Key from configuration

**ID**: `trust-sign.private-key-resolution.key-from-configuration`

- **WHEN** `KONG_SIGNING_CERT_KEY` is not set
- **THEN** tokens verify against the public key corresponding to the PEM file at `config.private_key_location`

#### Scenario: Environment variable overrides configuration

**ID**: `trust-sign.private-key-resolution.env-var-overrides-configuration`

- **WHEN** `KONG_SIGNING_CERT_KEY` is set to a key file path
- **THEN** tokens verify against that key, even if `config.private_key_location` points to a different file

### Requirement: Response digest generation

**ID**: `trust-sign.response-digest-generation`

With `direction = response`, when the response has no `Content-Digest` header, the plugin SHALL compute the SHA-256 digest of the raw response body and set the `Content-Digest` response header to `sha-256=:<base64 digest>:` (standard base64 of the raw digest bytes).

#### Scenario: Missing Content-Digest with a non-empty upstream body

**ID**: `trust-sign.response-digest-generation.missing-digest-nonempty-upstream-body`

- **WHEN** the upstream response has a non-empty body and no `Content-Digest` header
- **THEN** the client response carries `Content-Digest: sha-256=:<base64(SHA-256(body))>:`

#### Scenario: Missing Content-Digest with an empty-string body

**ID**: `trust-sign.response-digest-generation.missing-digest-empty-string-body`

- **WHEN** the upstream response body is an empty string and `Content-Digest` is absent
- **THEN** the client response carries `Content-Digest` set to the SHA-256 digest of the empty string

#### Scenario: Upstream-supplied Content-Digest is preserved

**ID**: `trust-sign.response-digest-generation.upstream-supplied-digest-preserved`

- **WHEN** the upstream response already has a `Content-Digest` header
- **THEN** the header is passed through to the client unchanged

### Requirement: Response manifest signing

**ID**: `trust-sign.response-manifest-signing`

With `direction = response`, the plugin SHALL set the response header named by `config.signature_header_key` to a signed JWT, whether the response came from the upstream service or was generated by Kong (e.g. `request-termination` or another plugin's early exit). The manifest claims depend on the inbound request header `X-Edge-Token`: when present and parseable as a JWT, the claims `request_id`, `client_id`, `service_id`, and `digest` are copied from that token's payload; when absent, the manifest carries only `jwks_uri` (plus standard claims); when present but unparseable, the plugin rejects the exchange.

#### Scenario: Claims echoed from the inbound token

**ID**: `trust-sign.response-manifest-signing.claims-echoed-from-inbound-token`

- **WHEN** the inbound request carried a parseable JWT in `X-Edge-Token`
- **THEN** the response manifest's `request_id`, `client_id`, `service_id`, and `digest` claims equal those of the inbound token's payload, and `jwks_uri` is taken from this plugin instance's config

#### Scenario: Unparseable inbound token is rejected

**ID**: `trust-sign.response-manifest-signing.unparseable-inbound-token-rejected`

- **WHEN** the inbound request's `X-Edge-Token` header is not a parseable JWT
- **THEN** the client receives status 403 with a JSON body containing `message` = `"Bad token"` and an `error` field, and no signature header is set

#### Scenario: Missing inbound token produces a bare manifest

**ID**: `trust-sign.response-manifest-signing.missing-inbound-token-bare-manifest`

- **WHEN** the inbound request has no `X-Edge-Token` header
- **THEN** the response still carries the configured signature header with a JWT whose payload contains `jwks_uri` (if configured) and the standard claims, but no `request_id`, `client_id`, `service_id`, or `digest` claims

#### Scenario: Kong-generated responses are signed

**ID**: `trust-sign.response-manifest-signing.kong-generated-responses-are-signed`

- **WHEN** the response is generated by Kong itself rather than the upstream service (e.g. a Kong error response or an early exit from another plugin such as `request-termination`)
- **THEN** the plugin still sets the signature header per the other response-direction scenarios

### Requirement: Configuration schema

**ID**: `trust-sign.configuration-schema`

The plugin SHALL only apply to HTTP(S) traffic and SHALL enforce its config schema: `keyid`, `private_key_location`, and `signature_header_key` are required; `signature_header_key` defaults to `"X-Edge-Token"` when omitted; `direction` must be one of `request`/`response`; `alg` must be one of `RS256`/`RS512`/`ES256`/`ES512`; `hash_alg` must be one of `sha256`/`sha512`; `jwks_uri` is an optional string.

#### Scenario: Required fields enforced

**ID**: `trust-sign.configuration-schema.required-fields`

- **WHEN** a plugin config omits `keyid` or `private_key_location`
- **THEN** the configuration is rejected by schema validation

#### Scenario: Enumerated fields enforced

**ID**: `trust-sign.configuration-schema.enumerated-fields`

- **WHEN** a plugin config sets `direction`, `alg`, or `hash_alg` to a value outside its allowed set
- **THEN** the configuration is rejected by schema validation

## Interop / shared contract

This spec is the **source of truth** for the wire format consumed by `trust-verify-signature`. The shared contract:

- **Manifest token**: a JWS compact JWT carried in the header named by `signature_header_key` (default `X-Edge-Token`). Header fields: `alg`, `kid`. Payload claims: `request_id`, `client_id`, `service_id`, `digest`, `jwks_uri`, `jti`, `iat` (any of the first five may be absent per the requirements above).
- **Content-Digest header**: `<alg>=:<standard base64 of raw digest bytes>:`; this plugin always emits `sha-256` as the algorithm.
- **Response-direction input**: the response signer reads the inbound request's `X-Edge-Token` header (a fixed name, independent of `signature_header_key`) and echoes its `request_id`, `client_id`, `service_id`, and `digest` claims.

## Out of scope

- RFC 9421 HTTP message signatures (`Signature-Input`/`Signature` headers and the signature-base builder module): fully commented out in both phases.
- `x5c` certificate chain in the JWT header, the `KONG_SIGNING_CERT` env var, and public-key handling: only referenced by commented-out or unreachable code.
- `aud` and consumer (`consumerid`/`consumername`) claims: commented out.
- 403 rejection of responses when `X-Edge-Token` is missing: commented out in favor of the bare manifest.
- `signature_label` and `signature_input` config fields: commented out of the schema.
- `Content-Digest` parsing helper: present in the plugin's modules but never invoked by this plugin (consumed by the verify plugin).
