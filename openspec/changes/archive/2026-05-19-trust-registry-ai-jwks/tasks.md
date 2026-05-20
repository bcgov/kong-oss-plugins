## 1. Plugin Scaffolding

- [x] 1.1 Create plugin directory `plugins/trust-registry-ai-openspec/src/` with `schema.lua` defining the plugin name `trust-registry-ai-openspec` and an empty config record
- [x] 1.2 Create the rockspec file `plugins/trust-registry-ai-openspec/kong-plugin-trust-registry-ai-openspec-1.0.0-0.rockspec` with module declarations for handler, schema, and jwks modules

## 2. Core JWKS Logic

- [x] 2.1 Create `src/jwks.lua` with a function to query `kong.db.keys` and `kong.db.key_sets`, iterate over keys, and build the JWKS `keys` array
- [x] 2.2 Implement PEM-to-JWK conversion in `src/jwks.lua` using `resty.openssl.pkey.new(pem):tostring("public", "JWK")` with pcall error handling to skip malformed keys
- [x] 2.3 Implement JWK passthrough logic: if a key entity already has a `jwk` field populated, decode it and include it directly without conversion
- [x] 2.4 Implement `kid` population: use the key entity's `kid` field, falling back to `name` if `kid` is not set
- [x] 2.5 Implement keyset filtering: accept an optional `key_set` name parameter, resolve it via `kong.db.key_sets`, and filter keys by the matching set ID. Return 404 if the keyset name is not found.

## 3. Handler

- [x] 3.1 Create `src/handler.lua` with an `access` phase handler that extracts the optional `key_set` path parameter from `kong.router.get_route()` or `ngx.ctx.router_matches.uri_captures`
- [x] 3.2 Call the jwks module to build the JWKS response and return it via `kong.response.exit(200, body, headers)` with Content-Type `application/json`

## 4. Kong Declarative Configuration

- [x] 4.1 Add the plugin route entries to `local/kong-validate/kong.yaml` with the two paths (`/.well-known/jwks.json` and `~/keysets/(?<key_set>.+)/.well-known/jwks.json`) and GET method only

## 5. Validation

- [x] 5.1 Run the Kong validation Docker setup to confirm the plugin loads without errors
- [x] 5.2 Verify JWKS endpoint returns valid JSON with correct structure for the all-keys route
- [x] 5.3 Verify keyset-filtered route returns only keys for the specified keyset
