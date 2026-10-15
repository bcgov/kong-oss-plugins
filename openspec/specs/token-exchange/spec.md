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
`configured`/`verified_subject_token`), `target_privacy_zone_scope`
(optional string containing exactly one non-empty OAuth scope), `audience`
(optional string), and `timeout` (number, default `10000`). `expiration`
SHALL be greater than zero.

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
- **THEN** schema validation accepts it with `algorithm = RS256`, `expiration = 60`, `scopes` equal to an empty array, `scope_source = configured`, `target_privacy_zone_scope` unset, and `timeout = 10000`

#### Scenario: Scope source is enumerated

**ID**: `token-exchange.configuration-schema.scope-source-enum`

- **WHEN** `scope_source` is neither `configured` nor `verified_subject_token`
- **THEN** schema validation rejects the configuration

#### Scenario: Target privacy-zone scope is singular

**ID**: `token-exchange.configuration-schema.target-privacy-zone-scope`

- **WHEN** `target_privacy_zone_scope` is set
- **THEN** schema validation accepts exactly one non-empty, whitespace-free OAuth scope and rejects empty or compound values

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
- **THEN** no token-endpoint request is made and the client receives a structured 401 response with `error.code = "E5"`

#### Scenario: Nonmatching Authorization is rejected

**ID**: `token-exchange.subject-token-extraction.nonmatching-header-rejected`

- **WHEN** the inbound `Authorization` value does not contain the exact case-sensitive pattern `Bearer` followed by whitespace and at least one character
- **THEN** no token-endpoint request is made and the client receives a structured 401 response with `error.code = "E5"`

#### Scenario: Embedded Bearer substring is accepted

**ID**: `token-exchange.subject-token-extraction.embedded-bearer-substring-accepted`

- **WHEN** an `Authorization` value contains arbitrary text followed later by `Bearer <token>`
- **THEN** the token endpoint receives `<token>` as the `subject_token`

### Requirement: Audience transfer

**ID**: `token-exchange.audience-transfer`

When `jwt-keycloak` has placed a verified subject token in Kong's shared
request context, the plugin SHALL derive exchange audiences only from that
token and the configured consumer `audience`. The verified subject `aud` SHALL
be accepted as either a string or an array of non-empty strings. Audience
values SHALL use exact, case-sensitive comparison.

The verified subject audience SHALL contain `config.client_id`. The plugin
SHALL retain that SDX exchange client and remove duplicate values. When the
optional `config.audience` is set to a non-empty string, the plugin SHALL merge
it with the verified subject audiences and place it first and exactly once.
The SDX exchange client SHALL appear exactly once. The plugin SHALL send every
resulting value as a repeated RFC 8693 `audience` form parameter. Retaining the
SDX exchange client allows the exchanged token to authorize a subsequent SDX
token exchange.

When verified-token context is unavailable, the plugin SHALL preserve its
legacy direct-use behavior by requesting only `config.audience` when set.

#### Scenario: Configured and original audiences are combined

**ID**: `token-exchange.audience-transfer.configured-and-original`

- **WHEN** `config.client_id = sdx-client`, `config.audience = provider-resource`, and the verified subject `aud` is `[requesting-client, sdx-client, provider-resource, optional-client, requesting-client]`
- **THEN** the exchange request contains the ordered audience values `[provider-resource, requesting-client, sdx-client, optional-client]`, each encoded as a separate `audience` parameter

#### Scenario: A string subject audience authorizes exchange

**ID**: `token-exchange.audience-transfer.string-audience`

- **WHEN** the verified subject `aud` is the string equal to `config.client_id` and `config.audience` is not set
- **THEN** the exchange request contains only `[config.client_id]`

#### Scenario: SDX exchange client is retained for a subsequent exchange

**ID**: `token-exchange.audience-transfer.exchange-client-retained`

- **WHEN** the verified subject audience authorizes `config.client_id`
- **THEN** the exchange request contains `config.client_id` exactly once so that the exchanged token can authorize a subsequent SDX token exchange

#### Scenario: Configured consumer audience is optional

**ID**: `token-exchange.audience-transfer.configured-audience-optional`

- **WHEN** verified-token context exists and `config.audience` is absent or empty
- **THEN** the exchange request contains the deduplicated verified subject audiences, including `config.client_id`
- **AND WHEN** `config.audience` equals an existing verified subject audience
- **THEN** that audience is requested exactly once

#### Scenario: Subject token does not authorize the SDX exchange client

**ID**: `token-exchange.audience-transfer.subject-not-authorized`

- **WHEN** the verified subject `aud` does not contain an exact value equal to `config.client_id`
- **THEN** the token endpoint is not called and the client receives status 400, `error.code = SDX_TOKEN_EXCHANGE_NOT_AUTHORIZED`, a generic message containing the Kong request ID, and an `X-Kong-Request-Id` response header with the same value
- **AND** the public response omits audience values, the configured client ID, tokens, and identity-provider details, while the plugin log records the request ID and diagnostic reason

#### Scenario: Malformed subject audience is rejected

**ID**: `token-exchange.audience-transfer.malformed-subject-audience`

- **WHEN** the verified subject `aud` is missing, empty, neither a string nor an array, or contains a non-string or empty value
- **THEN** the request follows the same correlated, redacted 400 authorization-error contract and the token endpoint is not called

#### Scenario: Repeated audience parameters are encoded

**ID**: `token-exchange.audience-transfer.repeated-parameters`

- **WHEN** the normalized audience list contains more than one value
- **THEN** the form body contains one `audience=<value>` parameter for each value rather than one joined value

#### Scenario: Configured audience remains the direct-use fallback

**ID**: `token-exchange.audience-transfer.configured-fallback`

- **WHEN** no verified subject token exists in shared request context and `config.audience` is set
- **THEN** the exchange request contains that configured audience once

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

#### Scenario: Configured audience is conditional for direct use

**ID**: `token-exchange.token-endpoint-request.audience-conditional`

- **WHEN** normalized verified-token audiences are not supplied and `audience` is set to a string
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

When `target_privacy_zone_scope` is set in verified-subject-token mode,
the plugin SHALL append that administrator-provisioned scope after the verified
subject scopes and de-duplicate the complete outgoing set. It SHALL ignore this
field in configured-scope mode so the meaning of `config.scopes` does not
change. The field is supplied by trusted control-plane configuration, never by
the calling consumer.

When a successful token response omits `scope`, the plugin SHALL treat the
granted scope set as identical to the requested set. When the response includes
a different scope set, the plugin SHALL log a warning and continue.

#### Scenario: Verified subject scopes are transferred

**ID**: `token-exchange.scope-transfer.verified-subject-scopes`

- **WHEN** verified-token context has a non-empty string `scope` claim with duplicate values
- **THEN** each verified subject scope is sent once and configured scopes are not sent

#### Scenario: Target provider privacy-zone scope is composed once

**ID**: `token-exchange.scope-transfer.target-privacy-zone-scope`

- **WHEN** verified subject scopes are valid and `target_privacy_zone_scope` is provisioned
- **THEN** the exchange request contains the verified subject scopes plus exactly one instance of the target privacy-zone scope, without configured fallback scopes

#### Scenario: Configured-scope behavior is unchanged

**ID**: `token-exchange.scope-transfer.configured-scope-compatibility`

- **WHEN** `scope_source = configured` and `target_privacy_zone_scope` is also present
- **THEN** the exchange request continues to use only `config.scopes`

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

#### Scenario: Invalid target is an SDX configuration failure

**ID**: `token-exchange.configuration-error.invalid-target`

- **WHEN** the token endpoint rejects a requested audience with OAuth error `invalid_target`
- **THEN** the client receives status 500, `error.code = SDX_TOKEN_EXCHANGE_CONFIGURATION_ERROR`, a generic message containing the Kong request ID, and an `X-Kong-Request-Id` response header with the same value
- **AND** exact requested audiences and identity-provider diagnostics remain only in the plugin log

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
description. Diagnostic detail SHALL log the requested scopes, audience, IdP
status, and OAuth error code without logging the error description or
duplicating the request ID already present on the enclosing Kong log record.

#### Scenario: Invalid scope is correlated and redacted

**ID**: `token-exchange.configuration-error.invalid-scope`

- **WHEN** the token endpoint returns `invalid_scope`
- **THEN** the client receives the correlated redacted configuration error and internal diagnostics retain only the approved diagnostic fields

#### Scenario: Other token errors retain the generic failure response

**ID**: `token-exchange.configuration-error.non-scope-errors-unchanged`

- **WHEN** the token endpoint returns an OAuth error other than `invalid_scope`
- **THEN** the client receives the generic status 500 token-exchange failure with its existing public error code

## Deployment prerequisite

Before provisioning `target_privacy_zone_scope`, the token-exchange client in
the target Keycloak realm must be permitted to request every provider
privacy-zone client scope that SDX routes can target. Deploy the plugin first,
then provision and preview the portal configuration, re-provision existing SDX
connections, and require a successful exchange before enabling the cutover. An
`invalid_scope` response remains a redacted, correlated configuration error.

## Out of scope

- Token introspection mentioned in the repository plugin summary: no introspection flow is implemented.
- The packaged `client_token` module's separate client-credentials request, including its singular `scope` and runtime-only `timeout` inputs: the access handler never invokes this module.
- Direct calls to exported Lua helpers with nil or schema-invalid configuration: Kong schema validation prevents those inputs on the plugin request path.
- An `x5c` certificate chain in the client assertion header: the only implementation is commented out.
