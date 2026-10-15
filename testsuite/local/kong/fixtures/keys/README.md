# Signing key fixtures

Generated once for shared Playwright / Kong plugin tests.

| File | How generated |
|---|---|
| `rsa-2048.pem` / `.pub.pem` | `openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048` + `openssl pkey -pubout` |
| `rsa-3072.pem` / `.pub.pem` | `openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072` + `openssl pkey -pubout` |
| `ec-p256.pem` / `.pub.pem` | `openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256` + `openssl pkey -pubout` |
| `ec-p384.pem` / `.pub.pem` | `openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-384` + `openssl pkey -pubout` |
| `ec-p521.pem` / `.pub.pem` | `openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-521` + `openssl pkey -pubout` |
| `*.jwks.json` | Node `crypto.createPublicKey(…).export({ format: "jwk" })` with `kid` = file stem, `use=sig` |
| `malformed.jwks.json` | Hand-written: a `keys` entry with `kid: "malformed"` whose `n` contains characters outside the base64url alphabet (fails key construction rather than just failing to verify), for testing malformed-JWK rejection |

Do not regenerate casually — plugins and tests may pin `kid` / paths. Add new keys alongside; do not replace existing ones without updating callers.

mTLS client-certificate fixtures (client CA + leaf certs with various subject
DNs) live in [`mtls/`](mtls/README.md).
