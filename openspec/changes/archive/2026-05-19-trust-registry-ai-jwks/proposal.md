## Why

SDX Edge Server hosts need to publish their public keys so that other Edge Servers can validate JSON Web Signature (JWS) documents. Today there is no standardised JWKS endpoint backed by Kong's native `keys` and `keysets` entities, forcing operators to manage key distribution out-of-band.

## What Changes

- Add a new Kong plugin (`trust-registry-ai-openspec`) that serves a JWKS (RFC 7517) document from Kong's `keys` and `keysets` entities.
- Expose two GET routes:
  - `/.well-known/jwks.json` — returns all keys across all keysets.
  - `/keysets/{key_set}/.well-known/jwks.json` — returns only the keys belonging to the named keyset.
- Convert PEM-formatted public keys to JWK objects on-the-fly so the response always contains valid JWK entries.
- The plugin requires no configuration parameters.

## Capabilities

### New Capabilities

- `jwks-endpoint`: Serves a JWKS document from Kong's keys/keysets entities, with optional keyset filtering and PEM-to-JWK conversion.

### Modified Capabilities

(none)

## Impact

- **New plugin directory**: `plugins/trust-registry-ai-openspec/` with `handler.lua`, `schema.lua`, and rockspec.
- **Kong entities used**: `keys`, `key_sets` (read-only via Kong PDK / Admin API).
- **Dependencies**: `resty.openssl.pkey` (PEM→JWK conversion), `cjson` (JSON encoding).
- **Routes**: Two new GET paths must be configured on a service/route that loads this plugin.
