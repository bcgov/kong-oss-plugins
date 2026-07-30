# Signing key fixtures

Generated once for shared Playwright / Kong plugin tests.

| File | How generated |
|---|---|
| `rsa-2048.pem` / `.pub.pem` | `openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048` + `openssl pkey -pubout` |
| `ec-p256.pem` / `.pub.pem` | `openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256` + `openssl pkey -pubout` |
| `*.jwks.json` | Node `crypto.createPublicKey(…).export({ format: "jwk" })` with `kid` = file stem, `use=sig` |

Do not regenerate casually — plugins and tests may pin `kid` / paths. Add new keys alongside; do not replace existing ones without updating callers.
