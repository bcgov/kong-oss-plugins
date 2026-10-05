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
of strings, default empty), `scope_source` (string, default `configured`, one of
`configured`/`verified_subject_token`), `audience` (optional string), and
`timeout` (number, default `10000`). `expiration` SHALL be greater than zero.

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
- **THEN** schema validation accepts it with `algorithm = RS256`, `expiration = 60`, `scopes` equal to an empty array, `scope_source = configured`, and `timeout = 10000`

#### Scenario: Scope source is enumerated

**ID**: `token-exchange.configuration-schema.scope-source-enum`

- **WHEN** `scope_source` is neither `configured` nor `verified_subject_token`
- **THEN** schema validation rejects the configuration

#### Scenario: Nonpositive expiration is rejected

**ID**: `token-exchange.configuration-schema.nonpositive-expiration-accepted`

- **WHEN** `expiration` is zero or a negative number
- **THEN** schema validation rejects the configuration

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

- **WHEN** `private_key_location` is readable but does not contain a parseable private key
- **THEN** every request using that configuration is terminated before a token-endpoint request is made, no upstream `Authorization` header is set, and the client receives status 500 with an error explaining that the private key could not be parsed

#### Scenario: Unreadable key path aborts the request

**ID**: `token-exchange.private-key-resolution.unreadable-key-aborts-request`

- **WHEN** `private_key_location` names a file that cannot be read
- **THEN** every request using that configuration is terminated before a token-endpoint request is made, no upstream `Authorization` header is set, and the client receives status 500 with an error explaining that the private key could not be read

### Requirement: Subject token extraction

**ID**: `token-exchange.subject-token-extraction`

The plugin SHALL derive the exchange `subject_token` by applying the
case-sensitive Lua pattern `Bearer%s+(.+)` to the inbound `Authorization` header.
The pattern is not anchored to the beginning of the header. The default
deployment SHALL run token validation before token exchange; the
direct-invocation cases below therefore do not occur in that supported pipeline.

#### Scenario: Bearer token becomes the subject token

**ID**: `token-exchange.subject-token-extraction.bearer-token-extracted`

- **WHEN** the inbound request has `Authorization: Bearer <token>` with at least one whitespace character after `Bearer` and a non-empty `<token>`
- **THEN** the token endpoint receives `<token>` as the `subject_token`

#### Scenario: Missing Authorization header is handled

**ID**: `token-exchange.subject-token-extraction.missing-header-handled`

- **WHEN** the inbound request has no `Authorization` header
- **THEN** no token-endpoint request is made and the client receives a structured 401 response with `error.code = "E4"`

#### Scenario: Nonmatching Authorization is rejected

**ID**: `token-exchange.subject-token-extraction.nonmatching-header-rejected`

- **WHEN** the inbound `Authorization` value does not contain the exact case-sensitive pattern `Bearer` followed by whitespace and at least one character
- **THEN** no token-endpoint request is made and the client receives a structured 401 response with `error.code = "E4"`

#### Scenario: Embedded Bearer substring is accepted

**ID**: `token-exchange.subject-token-extraction.embedded-bearer-substring-accepted`

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
extraction succeeds. The HTTP timeout SHALL equal `config.timeout`, which
defaults to 10,000 milliseconds when omitted. Unit tests MAY call
`do_token_exchange` (`require "token_exchange"`).

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

- **WHEN** `scope_source = configured` and `scopes` contains one or more strings
- **THEN** the exchange form contains one `scope` parameter formed by joining them in array order with single spaces; when `scopes` is empty, the parameter is omitted

#### Scenario: Configured token-endpoint timeout is used

**ID**: `token-exchange.token-endpoint-request.timeout-field-unavailable`

- **WHEN** an administrator configures `timeout` to a number of milliseconds
- **THEN** schema validation accepts the field and the token-endpoint HTTP request uses that timeout; when omitted, the request uses 10,000 milliseconds

### Requirement: Verified subject scope transfer

**ID**: `token-exchange.scope-transfer`

When `scope_source = verified_subject_token`, the plugin SHALL obtain scopes
only from the `scope` claim in `kong.ctx.shared.jwt_keycloak_token`, split the
string on whitespace, remove duplicates while retaining first-seen order, and
send that list in the token-exchange request. It SHALL NOT fall back to
`config.scopes` when verified-token context is missing or invalid.

When a successful token response omits `scope`, the plugin SHALL treat the
granted scope set as identical to the requested set. When the response includes
a different scope set, the plugin SHALL log a warning and continue.

#### Scenario: Verified subject scopes are transferred

**ID**: `token-exchange.scope-transfer.verified-subject-scopes`

- **WHEN** verified-token context has a non-empty string `scope` claim with duplicate values
- **THEN** each verified subject scope is sent once and configured scopes are not sent

#### Scenario: Invalid verified-token scope context fails closed

**ID**: `token-exchange.scope-transfer.invalid-subject-scope`

- **WHEN** verified-token context is absent or its `scope` claim is missing, non-string, or empty
- **THEN** no token-endpoint request is made and the client receives status 500 with `error.code = "E4"`

#### Scenario: Transferred scopes are sent to the token endpoint

**ID**: `token-exchange.scope-transfer.exchange-request`

- **WHEN** verified subject scopes are supplied to the exchange
- **THEN** the exchange form contains those scopes once each and does not contain configured fallback scopes

#### Scenario: Omitted response scope is accepted

**ID**: `token-exchange.scope-transfer.omitted-response-scope`

- **WHEN** a successful token response omits its `scope` member
- **THEN** the plugin accepts the response without logging a scope-mismatch warning

#### Scenario: Response scope order does not matter

**ID**: `token-exchange.scope-transfer.response-scope-order`

- **WHEN** a successful token response declares the requested scopes in a different order
- **THEN** the plugin accepts the response without logging a scope-mismatch warning

#### Scenario: Response scope mismatch is reported

**ID**: `token-exchange.scope-transfer.response-scope-mismatch`

- **WHEN** a successful token response declares a scope set different from the requested set
- **THEN** the plugin logs a warning describing both sets and continues with the returned token

#### Scenario: JWT query parameter is disabled for scope-transfer routes

**ID**: `token-exchange.scope-transfer.query-token-rejected`

- **WHEN** an SDX route receives a valid JWT only through the `jwt` query parameter
- **THEN** `jwt-keycloak` rejects the request and token exchange is not attempted

### Requirement: Successful exchange

**ID**: `token-exchange.successful-exchange`

The plugin SHALL accept only an HTTP 200 token-endpoint response containing a
non-empty JSON string `access_token` as successful and SHALL replace the
upstream request's `Authorization` header with `Bearer <access_token>`. A
decoded response without a non-empty string `access_token` SHALL fail with
error code `E3`.

#### Scenario: Exchanged access token replaces inbound credentials

**ID**: `token-exchange.successful-exchange.access-token-replaces-authorization`

- **WHEN** the token endpoint returns status 200 with a JSON object containing string `access_token = <new-token>`
- **THEN** the request is proxied upstream with `Authorization: Bearer <new-token>`, replacing the inbound credential

#### Scenario: Additional token response members do not affect the request

**ID**: `token-exchange.successful-exchange.additional-members-ignored`

- **WHEN** a successful token response also contains members such as `token_type`, `expires_in`, or `scope`
- **THEN** only `access_token` is used to modify the upstream request

#### Scenario: Successful response without access token is rejected

**ID**: `token-exchange.successful-exchange.missing-access-token-rejected`

- **WHEN** the token endpoint returns status 200 with a JSON object whose `access_token` is missing, non-string, or empty
- **THEN** the request is not proxied and the client receives status 500 with `error` equal to an object containing `code = "E3"`

### Requirement: Original authorized party header

**ID**: `token-exchange.original-azp-header`

The plugin SHALL remove any inbound `X-SDX-Original-AZP` header before the
request is proxied. When `jwt-keycloak` has stored a verified subject token in
`kong.ctx.shared.jwt_keycloak_token` and its `azp` claim is a non-empty string,
the plugin SHALL set `X-SDX-Original-AZP` to that claim after a successful token
exchange. The plugin SHALL omit the header when no verified token or usable
`azp` claim is available. It SHALL never derive this header by decoding the
unverified bearer value directly.

#### Scenario: Verified original AZP is forwarded

**ID**: `token-exchange.original-azp-header.verified-azp-forwarded`

- **WHEN** the previously verified subject token contains `azp = <client>` and the token exchange succeeds
- **THEN** the upstream request contains `X-SDX-Original-AZP: <client>`, replacing any caller-supplied value

#### Scenario: Caller-supplied value is removed without a verified token

**ID**: `token-exchange.original-azp-header.unverified-value-removed`

- **WHEN** the request contains `X-SDX-Original-AZP` but no verified subject token is available
- **THEN** the token exchange may otherwise proceed, but the upstream request omits `X-SDX-Original-AZP`

#### Scenario: Missing or invalid AZP is omitted

**ID**: `token-exchange.original-azp-header.invalid-azp-omitted`

- **WHEN** the verified subject token has no `azp` claim or its value is not a non-empty string
- **THEN** the token exchange may otherwise proceed, but the upstream request omits `X-SDX-Original-AZP`

### Requirement: Token endpoint failure mapping

**ID**: `token-exchange.token-endpoint-failure-mapping`

When the token exchange returns a handled token-endpoint, assertion, or response error,
the plugin SHALL terminate the client request with a 5xx status and a JSON body
containing `message = "Token exchange failed"` and an `error` value described by
the scenarios below. It
SHALL not proxy the request upstream or replace its `Authorization` header.

#### Scenario: Transport failure maps to E1

**ID**: `token-exchange.token-endpoint-failure-mapping.transport-failure-e1`

- **WHEN** the HTTP client cannot obtain a response from the token endpoint
- **THEN** the client receives status 500 with `error` equal to an object containing `code = "E1"`

#### Scenario: Non-200 JSON response maps to E2 without detail

**ID**: `token-exchange.token-endpoint-failure-mapping.non-200-json-e2`

- **WHEN** the token endpoint returns any status other than 200 with a JSON body
- **THEN** the client receives status 500 with `error.code = "E2"` and no `error.detail` member

#### Scenario: Non-200 non-JSON response maps to E2 without detail

**ID**: `token-exchange.token-endpoint-failure-mapping.non-200-non-json-e2`

- **WHEN** the token endpoint returns any status other than 200 with an absent or non-JSON body
- **THEN** the client receives status 500 with `error.code = "E2"` and no `error.detail` member

#### Scenario: Invalid JSON in a 200 response maps to E3

**ID**: `token-exchange.token-endpoint-failure-mapping.invalid-200-json-e3`

- **WHEN** the token endpoint returns status 200 with a body that cannot be decoded as JSON
- **THEN** the client receives status 500 with `error` equal to an object containing `code = "E3"`

### Requirement: Invalid-scope configuration error

**ID**: `token-exchange.configuration-error`

When the token endpoint returns OAuth `invalid_scope`, the plugin SHALL return
status 500 with public code `SDX_TOKEN_EXCHANGE_CONFIGURATION_ERROR` and a
generic message containing Kong's request ID. The public response SHALL NOT
contain the requested scopes, audience, token-endpoint response, or OAuth error
description. Diagnostics SHALL log the request ID, requested scopes, audience,
IdP status, and OAuth error code without logging the error description.

#### Scenario: Invalid scope is correlated and redacted

**ID**: `token-exchange.configuration-error.invalid-scope`

- **WHEN** the token endpoint returns `invalid_scope`
- **THEN** the client receives the correlated redacted configuration error and internal diagnostics retain only the approved diagnostic fields

#### Scenario: Other token errors retain the generic failure response

**ID**: `token-exchange.configuration-error.non-scope-errors-unchanged`

- **WHEN** the token endpoint returns an OAuth error other than `invalid_scope`
- **THEN** the client receives the generic status 500 token-exchange failure with its existing public error code

## Out of scope

- Token introspection mentioned in the repository plugin summary: no introspection flow is implemented.
- The packaged `client_token` module's separate client-credentials request, including its singular `scope` and runtime-only `timeout` inputs: the access handler never invokes this module.
- Direct calls to exported Lua helpers with nil or schema-invalid configuration: Kong schema validation prevents those inputs on the plugin request path.
- An `x5c` certificate chain in the client assertion header: the only implementation is commented out.
