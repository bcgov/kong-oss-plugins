# token-exchange Specification

## Purpose

The token-exchange plugin replaces an inbound bearer token with an access token
obtained from a configured OAuth token endpoint during Kong's access phase. It
authenticates the exchange request with a signed JWT client assertion, sends an
RFC 8693-style form request, and either forwards the request with the exchanged
token or terminates it with an error response.

## Requirements

### Requirement: Configuration schema

**ID**: `token-exchange.configuration-schema`

The plugin SHALL apply only to HTTP(S) traffic and SHALL expose a `config` record
with these fields: `private_key_location` (required string), `client_id`
(required string), `token_endpoint` (required string), `algorithm` (string,
default `RS256`, one of `RS256`/`RS384`/`RS512`/`ES256`/`ES384`/`ES512`),
`expiration` (number, default `60`), `key_id` (optional string), `scopes` (array
of strings, default empty), `audience` (optional string), and `timeout` (number,
default `10000`). The schema imposes no range constraint on `expiration`.

#### Scenario: Required fields are enforced

**ID**: `token-exchange.configuration-schema.required-fields`

- **WHEN** a plugin config omits `private_key_location`, `client_id`, or `token_endpoint`
- **THEN** schema validation rejects the configuration

#### Scenario: Enumerated algorithms are enforced

**ID**: `token-exchange.configuration-schema.enumerated-algorithms`

- **WHEN** a plugin config sets `algorithm` to a value outside `RS256`, `RS384`, `RS512`, `ES256`, `ES384`, and `ES512`
- **THEN** schema validation rejects the configuration

#### Scenario: Canonical configuration is accepted

**ID**: `token-exchange.configuration-schema.canonical-config-accepted`

- **WHEN** a config supplies valid strings for `private_key_location`, `client_id`, and `token_endpoint` and omits all optional fields
- **THEN** schema validation accepts it with `algorithm = RS256`, `expiration = 60`, `scopes` equal to an empty array, and `timeout = 10000`

#### Scenario: Nonpositive expiration is accepted

**ID**: `token-exchange.configuration-schema.nonpositive-expiration-accepted`

- **TAG**: quirk — the schema permits assertions that expire immediately or before they are issued
- **WHEN** `expiration` is zero or a negative number
- **THEN** schema validation accepts the configuration and the assertion's `exp` claim equals `iat + expiration`

### Requirement: Client assertion contents

**ID**: `token-exchange.client-assertion-contents`

The plugin SHALL authenticate to the token endpoint with a compact JWS client
assertion. Its protected header SHALL contain `alg` equal to `config.algorithm`
and SHALL contain `kid` only when `config.key_id` is set. Its payload SHALL
contain `iss` and `sub` equal to `config.client_id`, `aud` equal to
`config.token_endpoint`, `iat` equal to the current Unix time in seconds, `exp`
equal to `iat + config.expiration`, and a fresh `jti` represented by 32
hexadecimal characters. The signature SHALL cover the base64url-encoded header
and payload, use the SHA-256, SHA-384, or SHA-512 digest identified by the `alg`
label, and use JWA raw `r || s` encoding when the configured PEM key is
elliptic-curve.

#### Scenario: Default assertion metadata

**ID**: `token-exchange.client-assertion-contents.default-metadata`

- **WHEN** a schema-valid config omits `algorithm`, `expiration`, and `key_id`
- **THEN** the outbound assertion has three base64url segments, a header containing `alg = RS256` and no `kid`, payload claims `iss` and `sub` equal to the client ID and `aud` equal to the token endpoint, a fresh 32-character hexadecimal `jti`, and `exp = iat + 60`

#### Scenario: Configured assertion metadata

**ID**: `token-exchange.client-assertion-contents.configured-metadata`

- **WHEN** `key_id`, `algorithm`, and `expiration` are explicitly configured
- **THEN** the assertion header contains that `kid` and algorithm label, and its payload has `exp = iat + expiration`

#### Scenario: Signing digest matches the algorithm label

**ID**: `token-exchange.client-assertion-contents.non-sha256-label-uses-sha256`

- **WHEN** `algorithm` is `RS256`/`ES256`, `RS384`/`ES384`, or `RS512`/`ES512` and a client assertion is emitted
- **THEN** the signature uses SHA-256, SHA-384, or SHA-512 respectively, matching the protected-header algorithm label

#### Scenario: Algorithm and private key types must match

**ID**: `token-exchange.client-assertion-contents.algorithm-key-type-mismatch`

- **WHEN** an `RS*` label is configured with an elliptic-curve key or an `ES*` label is configured with an RSA key
- **THEN** no token-endpoint request is made and the client receives status 500 with an error explaining that the private key type does not match the signing algorithm

### Requirement: Private key resolution

**ID**: `token-exchange.private-key-resolution`

The plugin SHALL resolve the PEM signing key path from
`KONG_SIGNING_CERT_KEY` when that environment variable is set, otherwise from
`config.private_key_location`. Unit tests MAY call `create_client_assertion`
(`require "client_assertion"`).

#### Scenario: Configured private key signs the assertion

**ID**: `token-exchange.private-key-resolution.configured-key-signs-assertion`

- **WHEN** `private_key_location` names a readable valid PEM private key
- **THEN** the client assertion signature is produced by that key

#### Scenario: Signing key environment override is used

**ID**: `token-exchange.private-key-resolution.environment-override-ignored`

- **WHEN** `KONG_SIGNING_CERT_KEY` names a different key from `private_key_location`
- **THEN** the client assertion is signed by the key named by `KONG_SIGNING_CERT_KEY`

#### Scenario: Malformed key aborts the request

**ID**: `token-exchange.private-key-resolution.malformed-key-aborts-request`

- **WHEN** a previously unused `private_key_location` is readable but does not contain a parseable private key
- **THEN** no token-endpoint request is made, no upstream `Authorization` header is set, and the client receives status 500 with an error explaining that the private key could not be parsed

#### Scenario: Unreadable key path aborts the request

**ID**: `token-exchange.private-key-resolution.unreadable-key-generates-ephemeral-key`

- **WHEN** a previously unused `private_key_location` names a file that cannot be read
- **THEN** no token-endpoint request is made, no upstream `Authorization` header is set, and the client receives status 500 with an error explaining that the private key could not be read

### Requirement: Subject token extraction

**ID**: `token-exchange.subject-token-extraction`

The plugin SHALL derive the exchange `subject_token` by applying the
case-sensitive Lua pattern `Bearer%s+(.+)` to the inbound `Authorization` header.
The pattern is not anchored to the beginning of the header.

#### Scenario: Bearer token becomes the subject token

**ID**: `token-exchange.subject-token-extraction.bearer-token-extracted`

- **WHEN** the inbound request has `Authorization: Bearer <token>` with at least one whitespace character after `Bearer` and a non-empty `<token>`
- **THEN** the token endpoint receives `<token>` as the `subject_token`

#### Scenario: Missing Authorization header raises an unhandled failure

**ID**: `token-exchange.subject-token-extraction.missing-header-unhandled-failure`

- **TAG**: quirk — the code calls string matching on a nil header instead of rejecting the request deliberately
- **WHEN** the inbound request has no `Authorization` header
- **THEN** no token-endpoint request is made and the client receives a Kong-generated 5xx response rather than the plugin's structured 400 response

#### Scenario: Nonmatching Authorization omits the subject token

**ID**: `token-exchange.subject-token-extraction.nonmatching-header-omits-subject-token`

- **TAG**: quirk — malformed, differently cased, and non-Bearer credentials are forwarded to the IdP without a subject token
- **WHEN** the inbound `Authorization` value does not contain the exact case-sensitive pattern `Bearer` followed by whitespace and at least one character
- **THEN** the plugin still calls the token endpoint but omits `subject_token` from the form body

#### Scenario: Embedded Bearer substring is accepted

**ID**: `token-exchange.subject-token-extraction.embedded-bearer-substring-accepted`

- **TAG**: quirk — the extraction pattern is unanchored and can accept text before the Bearer credential
- **WHEN** an `Authorization` value contains arbitrary text followed later by `Bearer <token>`
- **THEN** the token endpoint receives `<token>` as the `subject_token`

### Requirement: Token endpoint request

**ID**: `token-exchange.token-endpoint-request`

The plugin SHALL send an HTTPS-verified `POST` to `config.token_endpoint` with
`Content-Type: application/x-www-form-urlencoded`, `Accept: application/json`,
and a form body whose parameter order is unspecified. The form SHALL contain
`client_id`, the generated `client_assertion`, `client_assertion_type` equal to
`urn:ietf:params:oauth:client-assertion-type:jwt-bearer`, `grant_type` equal to
`urn:ietf:params:oauth:grant-type:token-exchange`, `subject_token_type` and
`requested_token_type` each equal to
`urn:ietf:params:oauth:token-type:access_token`, plus `subject_token` when
extraction succeeds. The HTTP timeout SHALL be 10,000 milliseconds for every
schema-valid plugin configuration. Unit tests MAY call `do_token_exchange`
(`require "token_exchange"`).

#### Scenario: Standard exchange request

**ID**: `token-exchange.token-endpoint-request.standard-request`

- **WHEN** a request with a matching bearer credential is processed using a canonical config
- **THEN** the token endpoint receives one form-encoded POST with the required fixed parameters, configured client ID, generated client assertion, extracted subject token, JSON accept header, TLS verification enabled, and a 10,000 millisecond timeout

#### Scenario: Audience is conditional

**ID**: `token-exchange.token-endpoint-request.audience-conditional`

- **WHEN** `audience` is set to a string
- **THEN** the exchange form contains `audience` equal to that string; when `audience` is unset, the parameter is omitted

#### Scenario: Scopes are joined in configured order

**ID**: `token-exchange.token-endpoint-request.scopes-joined-in-order`

- **WHEN** `scopes` contains one or more strings
- **THEN** the exchange form contains one `scope` parameter formed by joining them in array order with single spaces; when `scopes` is empty, the parameter is omitted

#### Scenario: Configured token-endpoint timeout is used

**ID**: `token-exchange.token-endpoint-request.timeout-field-unavailable`

- **WHEN** an administrator configures `timeout` to a number of milliseconds
- **THEN** schema validation accepts the field and the token-endpoint HTTP request uses that timeout; when omitted, the request uses 10,000 milliseconds

### Requirement: Successful exchange

**ID**: `token-exchange.successful-exchange`

The plugin SHALL accept only an HTTP 200 token-endpoint response containing a
JSON string `access_token` as successful and SHALL replace the upstream
request's `Authorization` header with `Bearer <access_token>`. A decoded
response without a string `access_token` SHALL fail with error code `E3`.

#### Scenario: Exchanged access token replaces inbound credentials

**ID**: `token-exchange.successful-exchange.access-token-replaces-authorization`

- **WHEN** the token endpoint returns status 200 with a JSON object containing string `access_token = <new-token>`
- **THEN** the request is proxied upstream with `Authorization: Bearer <new-token>`, replacing the inbound credential

#### Scenario: Additional token response members do not affect the request

**ID**: `token-exchange.successful-exchange.additional-members-ignored`

- **WHEN** a successful token response also contains members such as `token_type`, `expires_in`, or `scope`
- **THEN** only `access_token` is used to modify the upstream request

#### Scenario: Successful response without access token is rejected

**ID**: `token-exchange.successful-exchange.missing-access-token-unhandled-failure`

- **WHEN** the token endpoint returns status 200 with a JSON object that has no string `access_token`
- **THEN** the request is not proxied and the client receives status 400 with `error` equal to an object containing `code = "E3"`

### Requirement: Token endpoint failure mapping

**ID**: `token-exchange.token-endpoint-failure-mapping`

When the token exchange returns a handled error, the plugin SHALL terminate the
client request with status 400 and a JSON body containing `message = "Token
exchange failed"` and an `error` value described by the scenarios below. It
SHALL not proxy the request upstream or replace its `Authorization` header.

#### Scenario: Transport failure maps to E1

**ID**: `token-exchange.token-endpoint-failure-mapping.transport-failure-e1`

- **WHEN** the HTTP client cannot obtain a response from the token endpoint
- **THEN** the client receives status 400 with `error` equal to an object containing `code = "E1"`

#### Scenario: Non-200 JSON response maps to E2 with detail

**ID**: `token-exchange.token-endpoint-failure-mapping.non-200-json-e2`

- **TAG**: quirk — every IdP status, including 5xx, is discarded and rewritten as client status 400
- **WHEN** the token endpoint returns any status other than 200 with a JSON body
- **THEN** the client receives status 400 with `error.code = "E2"` and `error.detail` equal to the decoded IdP body

#### Scenario: Non-200 non-JSON response maps to E2 without detail

**ID**: `token-exchange.token-endpoint-failure-mapping.non-200-non-json-e2`

- **WHEN** the token endpoint returns any status other than 200 with an absent or non-JSON body
- **THEN** the client receives status 400 with `error.code = "E2"` and no `error.detail` member

#### Scenario: Invalid JSON in a 200 response maps to E3

**ID**: `token-exchange.token-endpoint-failure-mapping.invalid-200-json-e3`

- **TAG**: quirk — a malformed successful IdP response is reported to the client as a 400-level request error
- **WHEN** the token endpoint returns status 200 with a body that cannot be decoded as JSON
- **THEN** the client receives status 400 with `error` equal to an object containing `code = "E3"`

## Out of scope

- Token introspection mentioned in the repository plugin summary: no introspection flow is implemented.
- The packaged `client_token` module's separate client-credentials request, including its singular `scope` and runtime-only `timeout` inputs: the access handler never invokes this module.
- Direct calls to exported Lua helpers with nil or schema-invalid configuration: Kong schema validation prevents those inputs on the plugin request path.
- An `x5c` certificate chain in the client assertion header: the only implementation is commented out.
