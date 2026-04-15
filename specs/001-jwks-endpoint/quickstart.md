# Quickstart: JWKS Endpoint Plugin

**Branch**: `001-jwks-endpoint` | **Date**: 2026-04-15

## Prerequisites

- Kong Gateway running (v3.x recommended)
- Admin API accessible (default: `http://localhost:8001`)

## 1. Install the Plugin

Build and install the rockspec:

```sh
cd plugins/trust-registry-ai
luarocks make kong-plugin-trust-registry-ai-1.0.0-0.rockspec
```

Add the plugin to Kong's configuration:

```sh
KONG_PLUGINS=bundled,trust-registry-ai
```

## 2. Register Keys in Kong

Register a keyset and key via the Admin API:

```sh
# Create a keyset
curl -s -X POST http://localhost:8001/key-sets \
  -d name=signing

# Register a JWK key in the keyset
curl -s -X POST http://localhost:8001/keys \
  -H "Content-Type: application/json" \
  -d '{
    "name": "my-signing-key",
    "kid": "my-signing-key-1",
    "set": {"name": "signing"},
    "jwk": "{\"kty\":\"RSA\",\"n\":\"...\",\"e\":\"AQAB\"}"
  }'
```

## 3. Create Routes and Enable Plugin

Create a service (placeholder, not proxied) and routes:

```sh
# Create a service (required by Kong, but not proxied)
curl -s -X POST http://localhost:8001/services \
  -d name=jwks-service \
  -d url=http://localhost

# Create route for all keys
curl -s -X POST http://localhost:8001/services/jwks-service/routes \
  -d "name=jwks-all" \
  -d "paths[]=/.well-known/jwks.json" \
  -d "methods[]=GET"

# Create route for keyset-scoped keys
curl -s -X POST http://localhost:8001/services/jwks-service/routes \
  -d "name=jwks-keyset" \
  -d "paths[]=~/keysets/(?<key_set>.+)/.well-known/jwks.json" \
  -d "methods[]=GET"

# Enable the plugin on the service
curl -s -X POST http://localhost:8001/services/jwks-service/plugins \
  -d name=trust-registry-ai
```

## 4. Verify

Retrieve all keys:

```sh
curl -s http://localhost:8000/.well-known/jwks.json | jq .
```

Expected output:

```json
{
  "keys": [
    {
      "kty": "RSA",
      "kid": "my-signing-key-1",
      "n": "...",
      "e": "AQAB"
    }
  ]
}
```

Retrieve keys for a specific keyset:

```sh
curl -s http://localhost:8000/keysets/signing/.well-known/jwks.json | jq .
```

## Validation

- [ ] `GET /.well-known/jwks.json` returns 200 with JWKS document
- [ ] `GET /keysets/signing/.well-known/jwks.json` returns 200 with
      filtered JWKS
- [ ] `GET /keysets/nonexistent/.well-known/jwks.json` returns 404
- [ ] Response Content-Type is `application/json`
- [ ] Each key in response has `kty` and `kid` fields
