## Context

Kong's `keys` and `key_sets` entities store cryptographic keys for an Edge Server, but there is no built-in way to publish those keys as a standard JWKS document. Other Edge Servers need to retrieve these public keys to verify JWS documents. The plugin `trust-registry-ai-openspec` will expose them via RFC 7517-compliant JWKS endpoints.

The plugin lives in `plugins/trust-registry-ai-openspec/` and follows the same layout as existing plugins (handler.lua, schema.lua, rockspec). It operates in the `access` phase, intercepts matched routes, and returns a JSON response directly — it does not proxy upstream.

## Goals / Non-Goals

**Goals:**

- Serve a JWKS document containing all public keys from Kong's `keys` entity.
- Support filtering by keyset via the `key_set` path parameter.
- Convert PEM-formatted public keys to JWK objects automatically using `resty.openssl.pkey`.
- Return keys that are already stored as JWK objects without conversion.
- Require zero plugin configuration parameters.

**Non-Goals:**

- Key management (create, update, delete) — that is the Admin API's responsibility.
- Caching or TTL headers — out of scope for the initial implementation.
- Support for private key export — only public key material is served.
- Support for symmetric keys (oct type) — only asymmetric keys (RSA, EC) are in scope.

## Decisions

### 1. Use `access` phase to short-circuit the request

**Decision**: Handle the entire request in the `access` phase via `kong.response.exit()`.

**Rationale**: The plugin produces a self-contained JSON response and does not need upstream proxying. The `access` phase is the standard point for plugins that generate responses directly. This matches the pattern used by other plugins in this repo (e.g., trust-hello uses `certificate`/`access` phases).

**Alternative considered**: Using `content` phase — rejected because it requires more boilerplate and the `access` phase is simpler for direct responses.

### 2. Use `kong.db.keys` and `kong.db.key_sets` for data access

**Decision**: Query Kong's database layer directly via `kong.db.keys:each()` and `kong.db.key_sets:find_by_name()` (or equivalent page methods).

**Rationale**: The Kong PDK exposes the DAO layer at `kong.db.<entity>`, which is the supported way to access core entities from within a plugin. This avoids internal HTTP calls to the Admin API.

**Alternative considered**: Calling the Admin API via `resty.http` — rejected because it introduces a network hop, requires Admin API access from the data plane, and is less reliable.

### 3. PEM-to-JWK conversion via `resty.openssl.pkey`

**Decision**: Use `resty.openssl.pkey.new(pem_string)` followed by `:tostring("public", "JWK")` to convert PEM keys to JWK format.

**Rationale**: `resty.openssl.pkey` is already a dependency in this repo and provides a high-level method to export a public key as a JWK JSON string. This avoids manual extraction of RSA/EC parameters and DER encoding, which is error-prone.

**Alternative considered**: Manual parameter extraction (n, e for RSA; x, y, crv for EC) from the pkey object — rejected because `tostring` with JWK format handles this internally and is less code.

### 4. Keyset filtering via Kong's DAO

**Decision**: When a `key_set` path parameter is present, resolve it to a key_set ID via `kong.db.key_sets`, then filter keys by that foreign key.

**Rationale**: Kong's `keys` entity has a `set` foreign key to `key_sets`. Querying `kong.db.keys:each()` and filtering by `set.id` is straightforward. Alternatively, use `kong.db.keys:page()` with a filter if Kong's DAO supports it for the `set` field.

### 5. Response format

**Decision**: Return `{ "keys": [...] }` with Content-Type `application/json`. Each key object includes `kty`, `kid`, `alg`, `use`, and the key-type-specific fields.

**Rationale**: This matches the JWKS format defined in RFC 7517 Section 5. The `kid` field is populated from the Kong key entity's `kid` field (or `name` as fallback).

## Risks / Trade-offs

- **[Performance on large key sets]** → Iterating all keys via `kong.db.keys:each()` on every request could be slow if hundreds of keys exist. Mitigation: This is acceptable for the initial implementation; caching can be added later if needed.
- **[PEM conversion failure]** → If a PEM key is malformed, `resty.openssl.pkey.new()` will error. Mitigation: Wrap in pcall, log the error, and skip the malformed key rather than failing the entire response.
- **[Key set not found]** → If the `key_set` path parameter doesn't match any keyset. Mitigation: Return a 404 with a clear error message.
- **[No keys available]** → If there are no keys (or none for the requested keyset). Mitigation: Return a valid JWKS document with an empty `keys` array — this is valid per RFC 7517.
