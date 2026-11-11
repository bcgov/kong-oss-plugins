# trust-verify-signature coverage map

> Review aid only — not normative. Clean-room test generation uses spec.md alone.

| Surface | Kind | Disposition |
|---|---|---|
| `config.direction` | config | Requirement: Direction gating |
| `config.signature_header_key` | config | Requirements: Request/Response signature verification; Configuration schema (`signature-header-key-defaults-to-x-edge-token`) |
| `config.allowed_jwks_uri_prefix` | config | Requirement: Issuer key discovery (`jwks-uri-not-allowed-401`, `allowed-jwks-uri-used`); Configuration schema (`allowed-jwks-uri-prefix-required`) |
| `config.manifest_type` | config | Requirement: Content-digest manifest check |
| `config.iss_key_grace_period` | config | Requirement: Issuer key discovery (`missing-kid-refreshes-after-grace`, `missing-kid-no-refresh-within-grace`) |
| `protocols` restriction (HTTP/HTTPS typedef) | config | Requirement: Configuration schema (prose) |
| Request header `<signature_header_key>` | input | Requirement: Request signature verification |
| Response header `<signature_header_key>` | input | Requirement: Response signature verification |
| Request `Content-Digest` header | input | Requirement: Content-digest manifest check (`matching-content-digest-accepted`, `mismatched-content-digest-400`); request direction only |
| Response `Content-Digest` header | input | Not consumed — content-digest checks are request-only (`response-direction-skips-checks`) |
| Token header `kid` | input | Requirement: Issuer key discovery (key selection; `unknown-kid-401`) |
| Token header `alg` | input | Requirement: Issuer key discovery (verification algorithm); unsupported values fail parse under `request-verification.unparseable-token-401` |
| Token payload claim `jwks_uri` | input | Requirement: Issuer key discovery (`allowed-jwks-uri-used`, `jwks-uri-not-allowed-401`, `jwks-cache-keyed-by-uri`) |
| Token payload claim `digest` | input | Requirement: Content-digest manifest check (`missing-digest-claim-401`, `matching-content-digest-accepted`, `mismatched-content-digest-400`); request direction only |
| JWKS endpoint response (status, JSON shape, JWK entries) | input | Requirement: Issuer key discovery (`jwks-fetch-failure-401`, `malformed-jwk-401`, `signature-mismatch-401`) |
| Upstream response status (any code, incl. Kong-generated) | input | Requirement: Response signature verification (prose: verified regardless of status) |
| `X-Trust-Verify-Signature-Req` request header (`OK`) | output | Requirement: Request signature verification |
| `X-Trust-Verify-Signature-Res` response header (`OK`) | output | Requirement: Response signature verification |
| Signature header pass-through on success | output | Requirements: Request/Response signature verification (THEN clauses) |
| 400/401 early exits with JSON `message` body | output | Requirements: Request/Response verification, Issuer key discovery, Content-digest manifest check |
