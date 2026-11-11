# token-exchange mock fixtures

`mock-server.mjs` records token-endpoint requests by `client_id` and returns
deterministic success and failure responses for the spec-driven Playwright
suite.

The self-signed TLS certificate used to verify that the plugin rejects an
untrusted token endpoint was generated with:

```sh
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout tls-key.pem -out tls-cert.pem -days 3650 \
  -subj "/CN=token-exchange-mock" \
  -addext "subjectAltName=DNS:token-exchange-mock"
```
