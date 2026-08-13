# mTLS client-certificate fixtures

Client-cert PKI for mTLS plugin tests (`mtls-auth`, `mtls-acl`, interop).
The Kong data planes trust `client-ca.crt`
(`KONG_NGINX_PROXY_SSL_CLIENT_CERTIFICATE` in
`testsuite/local/kong/.env.dp.local`, mode `optional_no_ca`), so on the TLS
proxy entry point (`https://kong.localtest.me:8443`) `$ssl_client_verify` is:

- `NONE` — no client certificate presented
- `SUCCESS` — any leaf below signed by `client-ca`
- `FAILED:…` — `untrusted.crt` (signed by `untrusted-ca`, which Kong does not trust)

In-container path: `/tmp/kong/fixtures/keys/mtls/…`. From Playwright, use
`mtlsClientCert(name)` / `mtlsProxyRequest` in `testsuite/helpers/kong.ts`.

## Inventory

Subject DNs below are the nginx `$ssl_client_s_dn` (RFC 2253) renderings —
note they are in reverse order of the openssl `-subj` used to generate them.

| Cert (`.crt`/`.key`) | Signed by | Subject DN as nginx renders it | Purpose |
|---|---|---|---|
| `client-ca` | self | `CN=Kong e2e Client CA,O=Kong e2e Test,C=US` | CA the Kong DPs trust |
| `untrusted-ca` | self | `CN=Kong e2e Untrusted CA,O=Kong e2e Test,C=US` | CA the Kong DPs do not trust |
| `alice` | client-ca | `CN=Alice Example,O=Example Org,C=US` | happy path; has CN and O |
| `comma-cn` | client-ca | `CN=Smith\, Jr.,O=Example Org,C=US` | RFC 2253 escaped comma in CN |
| `utf8-cn` | client-ca | `CN=Caf\C3\A9,O=Example Org,C=US` | hex-escaped UTF-8 in CN (decoded: `Café`) |
| `dup-cn` | client-ca | `CN=First,OU=Sales,CN=Second` | duplicate CN RDNs (string-last is `Second`); no O |
| `no-cn` | client-ca | `O=Example Org,C=US` | subject without CN |
| `no-org` | client-ca | `CN=NoOrg Example,C=US` | subject without O |
| `untrusted` | untrusted-ca | `CN=Mallory Example,O=Mallory Org,C=US` | fails verification (`FAILED:…`) |

Fingerprints and serials are not pinned here — derive them from the `.crt`
files at runtime (e.g. `node:crypto` `X509Certificate`).

## How generated

```sh
# CAs (client-ca shown; untrusted-ca identical with its own subject)
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out client-ca.key
openssl req -new -x509 -key client-ca.key \
  -subj "/C=US/O=Kong e2e Test/CN=Kong e2e Client CA" -days 7300 -sha256 -out client-ca.crt

# Leaves: same recipe per cert, varying -subj and the signing CA.
# Remember RFC 2253 reversal: nginx renders the -subj components in reverse
# order (e.g. dup-cn uses -subj "/CN=Second/OU=Sales/CN=First").
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out alice.key
openssl req -new -utf8 -key alice.key -subj "/C=US/O=Example Org/CN=Alice Example" -out alice.csr
openssl x509 -req -in alice.csr -CA client-ca.crt -CAkey client-ca.key \
  -CAcreateserial -days 7300 -sha256 -out alice.crt
rm alice.csr
```

Do not regenerate casually — tests derive expected values from these files,
and regenerating changes serials/fingerprints. Add new certs alongside; do
not replace existing ones without updating callers.
