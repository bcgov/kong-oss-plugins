# Research: JWKS Endpoint

**Branch**: `001-jwks-endpoint` | **Date**: 2026-04-15

## Decision 1: Plugin Name

**Decision**: `trust-registry-ai`

**Rationale**: Explicitly named by the project owner. The plugin
serves JWKS from Kong's internal key store as part of the trust
registry capability. The `-ai` suffix distinguishes it from the
existing `trust-registry` plugin directory.

**Alternatives considered**:
- `trust-jwks-endpoint`: Descriptive but not chosen by owner.
- `trust-keyserver`: Too generic.
- Reuse `trust-jwks`: Conflicts with existing plugin.

## Decision 2: PEM-to-JWK Conversion Approach

**Decision**: Create a self-contained `pem_to_jwk.lua` module within
the plugin using `resty.openssl.pkey`.

**Rationale**: The `resty.openssl.pkey` library is already used
throughout the repository (trust-hello, trust-sign, trust-jwks). It
provides key parameter extraction for RSA and EC key types. A
dedicated module keeps conversion logic isolated from handler logic,
following the pattern used by trust-sign (separate `sign.lua`,
`digest.lua` modules).

A `pem_to_jwks` module exists in the trust-registry plugin, but
per constitution (Generation Constraints, Excluded Source), that
directory is excluded from reference. The new module is independent.

**Approach**:
1. Load PEM string via `resty.openssl.pkey.new(pem_string)`.
2. Detect key type (RSA or EC) via `pkey:get_key_type()`.
3. Extract parameters: RSA (n, e) or EC (x, y, crv).
4. Encode parameters as base64url per RFC 7517.
5. Return a JWK table with `kty`, `kid`, and type-specific fields.

**Alternatives considered**:
- Inline conversion in handler.lua: Rejected because conversion
  logic is non-trivial and would reduce handler readability.
- Reference trust-registry's module as a runtime dependency:
  Rejected because it creates coupling to the excluded directory
  and violates the self-contained plugin convention.

## Decision 3: Kong DB API for Keys and Key Sets

**Decision**: Use `kong.db.keys` and `kong.db.key_sets` DAO methods.

**Rationale**: The Kong PDK provides database access via `kong.db`.
This is the standard pattern observed across plugins in this
repository. The relevant methods are:

- `kong.db.keys:each()` — iterate all keys (for unscoped endpoint).
- `kong.db.key_sets:select_by_name(name)` — look up keyset by name.
- `kong.db.keys:each_for_set({id = id})` — iterate keys for a
  specific keyset.

Key entity fields used:
- `kid` (string): Key identifier, maps to `kid` in JWK output.
- `jwk` (string or nil): JSON-encoded JWK, used directly if present.
- `pem` (table or nil): Contains `public_key` (PEM string), requires
  conversion if `jwk` is nil.
- `set` (table or nil): Foreign key reference to the key set.

**Alternatives considered**: None. `kong.db` is the only PDK-compliant
method for accessing Kong entities from plugin handlers.

## Decision 4: Route Capture Group Access

**Decision**: Use `kong.router.get_uri_captures()` to access the
`key_set` named capture group.

**Rationale**: The spec defines two routes:
- `/.well-known/jwks.json` (no capture)
- `~/keysets/(?<key_set>.+)/.well-known/jwks.json` (named capture)

The handler determines which route was matched by checking whether
the `key_set` named capture exists in the URI captures table. The
`kong.router.get_uri_captures()` PDK method is preferred over raw
`ngx.ctx.router_matches` per constitution Principle VII.

**Alternatives considered**:
- Parse `kong.request.get_path()` manually: Rejected as fragile and
  redundant given Kong's native capture support.

## Decision 5: Zero-Config Schema Pattern

**Decision**: Use empty `config.fields = {}` in schema.lua.

**Rationale**: FR-008 requires zero configuration parameters. The
trust-hello plugin demonstrates this exact pattern: a schema with
`protocols = typedefs.protocols_http` and an empty config record.
This is the established convention in this repository.

## Decision 6: Response Short-Circuit

**Decision**: The plugin operates in the `access` phase and returns
the JWKS response directly via `kong.response.exit()`. No upstream
proxy occurs.

**Rationale**: The JWKS endpoint is entirely self-contained — it reads
from Kong's key store and returns a JSON document. There is no
upstream service to proxy to. The `kong.response.exit()` pattern is
used by trust-hello and trust-sign for direct responses. This matches
spec assumption: "The plugin operates in the `access` phase of Kong's
request lifecycle and short-circuits the request."
