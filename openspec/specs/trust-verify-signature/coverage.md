# trust-verify-signature coverage map

> Review aid only — not normative. Clean-room test generation uses spec.md alone.

| Surface | Kind | Disposition |
|---|---|---|
| `config.direction` | config | Requirement: Direction gating |
| `config.signature_header_key` | config | Requirements: Request/Response signature verification; Configuration schema (`signature-header-key-defaults-to-x-edge-token`) |
| `config.manifest_type` | config | Requirement: Content-digest manifest check |
| `config.iss_key_grace_period` | config | Requirement: Configuration schema (accepted, no effect); Out of scope (unreachable refresh code) |
| `protocols` restriction (HTTP/HTTPS typedef) | config | Requirement: Configuration schema (prose) |
| Request header `<signature_header_key>` | input | Requirement: Request signature verification |
| Response header `<signature_header_key>` | input | Requirement: Response signature verification |
| Request `Content-Digest` header | input | Requirement: Content-digest manifest check — comparison unreachable, quirk `content-digest-check.present-cd-claim-500` |
| Token header `kid` | input | Requirement: Issuer key discovery (key selection; `unknown-kid-401`) |
| Token header `alg` | input | Requirement: Issuer key discovery (verification algorithm); unsupported values fail parse under `request-verification.unparseable-token-401` |
| Token payload claim `jwks_uri` | input | Requirement: Issuer key discovery (`jwks-uri-claim-trusted`); quirk `keys-shared-across-issuers` |
| Token payload claim `cd` | input | Requirement: Content-digest manifest check (both scenarios quirk-tagged) |
| JWKS endpoint response (status, JSON shape, JWK entries) | input | Requirement: Issuer key discovery (`jwks-fetch-failure-403`, `malformed-jwk-401`, `signature-mismatch-401`) |
| Upstream response status (any code, incl. Kong-generated) | input | Requirement: Response signature verification (prose: verified regardless of status); commented-out 200-only gate → Out of scope |
| `X-Trust-Verify-Signature-Req` request header (`OK`) | output | Requirement: Request signature verification |
| `X-Trust-Verify-Signature-Res` response header (`OK`) | output | Requirement: Response signature verification |
| Signature header pass-through on success | output | Requirements: Request/Response signature verification (THEN clauses) |
| 401/403 early exits with JSON `message` body | output | Requirements: Request/Response verification, Issuer key discovery, Content-digest manifest check |
| 500 runtime failures | output | Quirk `content-digest-check.present-cd-claim-500` |
| `key_conversion` module (JWK n/e → PEM) | dead code | Out of scope |
| Grace-period key refresh block in `signature.lua` | dead code | Out of scope |
| Commented-out non-200 response skip in `header_filter` | dead code | Out of scope |
| README description (RFC-9421 HTTP Message Signatures) | doc mismatch | Out of scope |
