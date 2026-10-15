# Shared test fixtures

Signing keys and JWKS files used by Playwright / Kong plugin tests.

## Layout

```text
fixtures/
  keys/
    rsa-2048.pem / rsa-2048.pub.pem / rsa-2048.jwks.json
    ec-p256.pem  / ec-p256.pub.pem  / ec-p256.jwks.json
    README.md    # how each file was generated
```

- **Inside Kong containers** (config values): `/tmp/kong/fixtures/keys/…`
  (`./local/kong` is mounted at `/tmp/kong` on CP/DP).
- **Reachable JWKS URL** (from Kong or other containers on the compose network):
  `http://kong:8000/__fixtures__/keys/<name>.jwks.json`
  The nginx load balancer (`kong` service) serves this directory statically —
  do **not** expose fixtures through a Kong route (the data plane deadlocks
  proxying to itself). From the host / Playwright: `${KONG_PROXY_URL}/__fixtures__/keys/…`.
- **Capture / hit-count JWKS URL** (prove a URI was or was not fetched):
  `http://kong:8000/__capture__/<id>` (host: `${KONG_PROXY_URL}/__capture__/<id>`).
  Nginx logs each request (unbuffered) to `fixtures/capture/hits.log` and serves
  `keys/rsa-2048.jwks.json`. Use a unique `<id>` per test (parallel workers share
  the log). Helper: `captureJwksUrl` / `countCaptureHits` in the plugin helper.
- **Dynamic JWKS writes** (grace-period cache tests): Playwright writes under
  `local/kong/fixtures/keys/` via the plugin helper. The `playwright` service
  bind-mounts that directory so in-container CI runs update the same files
  nginx serves at `/var/fixtures`.

Generate keys under `keys/` when a scenario needs them; do not change the
nginx location or compose mount for fixtures.
