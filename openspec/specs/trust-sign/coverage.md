# trust-sign coverage map

> Review aid only — not normative. Clean-room test generation uses spec.md alone.

| Surface | Kind | Disposition |
|---|---|---|
| `config.direction` (one_of request/response, optional) | config | Requirement: Direction gating |
| `config.jwks_uri` (optional) | config | Requirement: Request manifest signing; Requirement: Response manifest signing |
| `config.keyset_name` (required) | config | Requirement: JWT kid resolution; Requirement: Configuration schema |
| Kong keyset named by `config.keyset_name` | input | Requirement: JWT kid resolution |
| Keyset PEM `public_key` material | input | Requirement: JWT kid resolution (PEM match) |
| Keyset JWK material | input | Requirement: JWT kid resolution (JWK match) |
| Keyset missing / zero matches / duplicate matches | input | Requirement: JWT kid resolution (fail closed) |
| Private-key fingerprint after promotion/restart | input | Requirement: JWT kid resolution (new kid after restart) |
| `config.signature_header_key` (required, default `X-Edge-Token`) | config | Requirement: Request manifest signing; Requirement: Response manifest signing; Requirement: Configuration schema |
| `config.private_key_location` (required) | config | Requirement: Private key resolution; Requirement: Configuration schema |
| `config.alg` (one_of RS256/RS512/ES256/ES512, required) | config | Requirement: JWT token format; Requirement: Configuration schema (pending APS-4798: required; digests derived; key-type check) |
| `config.hash_alg` (ignored / removed) | config | Requirement: JWT token format; Requirement: Configuration schema (pending APS-4798: ignored or removed; digest from `alg`) |
| `config.hash_alg` unset at runtime | config | Closed by APS-4798 — digest derived from required `alg` |
| Private key type vs `config.alg` | config/runtime | Requirement: Configuration schema (pending APS-4798: fail 5xx when resolved key type mismatches `alg`) |
| `protocols` restricted to HTTP(S) | config | Requirement: Configuration schema |
| `Content-Digest` request header | input | Requirement: Request digest generation |
| Raw request body | input | Requirement: Request digest generation |
| `X-Edge-Token` request header (response direction) | input | Requirement: Response manifest signing |
| Service `client:`/`service:` tags | input | Requirement: Request manifest signing |
| Kong request ID | input | Requirement: Request manifest signing |
| `KONG_SIGNING_CERT_KEY` env var | input | Requirement: Private key resolution |
| `KONG_SIGNING_CERT` env var | input | Out of scope (only used by commented-out x5c code) |
| Response source (service vs. Kong-generated) | input | Requirement: Response manifest signing (Kong-generated responses are signed) |
| `Content-Digest` response header (from upstream) | input | Requirement: Response digest generation |
| Raw upstream response body | input | Requirement: Response digest generation |
| `Content-Digest` request header (set) | output | Requirement: Request digest generation |
| `Content-Digest` response header (set) | output | Requirement: Response digest generation |
| Signature header on request (`signature_header_key`) | output | Requirement: Request manifest signing |
| Signature header on response (`signature_header_key`) | output | Requirement: Response manifest signing |
| JWT header `kid` (from keyset match) | output | Requirement: JWT token format; Requirement: JWT kid resolution |
| 403 early exit on bad inbound token | output | Requirement: Response manifest signing |
| Commented-out RFC 9421 signing (`Signature-Input`/`Signature`, signature-base module) | dead code | Out of scope |
| Commented-out x5c / public-key handling | dead code | Out of scope |
| Commented-out `aud` / consumer claims | dead code | Out of scope |
| Commented-out 403 on missing `X-Edge-Token` | dead code | Out of scope |
| Commented-out `signature_label` / `signature_input` schema fields | dead code | Out of scope |
| Unused `Content-Digest` parse helper | dead code | Out of scope |
