# token-exchange coverage map

> Review aid only — not normative. Clean-room test generation uses spec.md alone.

| Surface | Kind | Disposition |
|---|---|---|
| HTTP(S)-only protocols | config | Requirement: Configuration schema |
| `config.private_key_location` (required string) | config | Requirement: Configuration schema; Requirement: Private key resolution |
| `config.client_id` (required string) | config | Requirement: Configuration schema; Requirement: Client assertion contents; Requirement: Token endpoint request |
| `config.token_endpoint` (required string) | config | Requirement: Configuration schema; Requirement: Client assertion contents; Requirement: Token endpoint request |
| `config.algorithm` (six-value enum, default `RS256`) | config | Requirement: Configuration schema; Requirement: Client assertion contents |
| `config.expiration` (number greater than zero, default `60`) | config | Requirement: Configuration schema; Requirement: Client assertion contents |
| `config.key_id` (optional string) | config | Requirement: Configuration schema; Requirement: Client assertion contents |
| `config.scopes` (string array, default empty) | config | Requirement: Configuration schema; Requirement: Token endpoint request |
| `config.audience` (optional string) | config | Requirement: Configuration schema; Requirement: Token endpoint request |
| `config.timeout` (number, default `10000`) | config/runtime | Requirement: Configuration schema; Requirement: Token endpoint request |
| PEM file at `private_key_location` | input | Requirement: Private key resolution |
| `KONG_SIGNING_CERT_KEY` environment variable | input | Requirement: Private key resolution |
| Current Unix time | input | Requirement: Client assertion contents |
| 16 random bytes per assertion | input | Requirement: Client assertion contents (`jti`) |
| Inbound `Authorization` header | input | Requirement: Subject token extraction |
| Missing inbound `Authorization` header | input | Requirement: Subject token extraction |
| Case-sensitive, unanchored `Bearer%s+(.+)` matching | input | Requirement: Subject token extraction |
| Token endpoint transport success/failure | input | Requirement: Token endpoint failure mapping |
| Token endpoint HTTP status | input | Requirement: Successful exchange; Requirement: Token endpoint failure mapping |
| Token endpoint response body | input | Requirement: Successful exchange; Requirement: Token endpoint failure mapping |
| Client assertion JWS header (`alg`, optional `kid`) | output | Requirement: Client assertion contents |
| Client assertion claims (`iss`, `sub`, `aud`, `jti`, `iat`, `exp`) | output | Requirement: Client assertion contents |
| Client assertion signature digest and key type | output | Requirement: Client assertion contents; Requirement: Private key resolution |
| Token endpoint URL, POST method, TLS verification, and timeout | output | Requirement: Token endpoint request |
| Token endpoint `Content-Type` and `Accept` headers | output | Requirement: Token endpoint request |
| Fixed token-exchange form parameters | output | Requirement: Token endpoint request |
| Conditional `subject_token`, `audience`, and `scope` form parameters | output | Requirement: Subject token extraction; Requirement: Token endpoint request |
| Unspecified form parameter order and form encoding | output | Requirement: Token endpoint request |
| Upstream `Authorization: Bearer <access_token>` replacement | output | Requirement: Successful exchange |
| Client status/body for transport failure (`E1`) | output | Requirement: Token endpoint failure mapping |
| Redacted client status/body for non-200 endpoint response (`E2`) | output | Requirement: Token endpoint failure mapping |
| Client status/body for invalid 200 JSON (`E3`) | output | Requirement: Token endpoint failure mapping |
| Handled 500 when the configured key file cannot be read | output | Requirement: Private key resolution |
| 5xx from missing request Authorization; handled 500 from malformed key contents; handled 400 from a missing response `access_token` | output | Requirement: Subject token extraction; Requirement: Private key resolution; Requirement: Successful exchange |
| Repository claim of token introspection | documented but unimplemented | Out of scope |
| Packaged `client_token.get_access_token_string` client-credentials flow | unintegrated code | Out of scope |
| `client_token` singular `config.scope` and runtime-only `config.timeout` | unintegrated inputs | Out of scope |
| Defensive nil/schema-invalid config branches in exported helpers | unreachable on plugin path | Out of scope |
| Commented-out assertion `x5c` header | dead code | Out of scope |
