# Comparison Report: trust-registry (Human) vs trust-registry-ai-openspec (OpenSpec AI)

**Date**: 2026-05-19  
**Scope**: Plugin code comparison + process observations for the OpenSpec run  
**OpenSpec change**: `openspec/changes/archive/2026-05-19-trust-registry-ai-jwks/` (archived)  
**Merged spec**: `openspec/specs/jwks-endpoint/spec.md`  
**Plugin**: `plugins/trust-registry-ai-openspec/`

For the Spec-Kit AI plugin, see [comparison-report.md](./comparison-report.md). For workflow comparison, see [speckit-vs-openspec.md](./speckit-vs-openspec.md).

## Validation (2026-05-19)

Local validation via `docker compose -f docker-compose.validate.yml up -d --build`:

| Check | Result |
|-------|--------|
| `GET /.well-known/jwks.json` | HTTP 200 — `keys` contains EC JWK (`ec-jwk-key-1`, passthrough) and RSA JWK (`rsa-pem-key-1`, PEM→JWK) |
| `GET /keysets/signing/.well-known/jwks.json` | HTTP 200 — `keys` contains only RSA key from `signing` keyset |

Example (abbreviated):

```json
// GET /.well-known/jwks.json
{ "keys": [
    { "kty": "EC", "kid": "ec-jwk-key-1", "crv": "P-256", ... },
    { "kty": "RSA", "kid": "rsa-pem-key-1", "e": "AQAB", "n": "..." }
]}

// GET /keysets/signing/.well-known/jwks.json
{ "keys": [
    { "kty": "RSA", "kid": "rsa-pem-key-1", "e": "AQAB", "n": "..." }
]}
```

**Conclusion:** Core MVP behavior works. PEM conversion and keyset filtering match the story.

---

## Structure

```text
plugins/trust-registry/                 # human
  src/handler.lua, pem_to_jwks.lua, schema.lua

plugins/trust-registry-ai-openspec/     # OpenSpec AI
  src/handler.lua, jwks.lua, schema.lua
```

OpenSpec split JWKS assembly into `jwks.lua`; the human plugin keeps logic in `handler.lua` with a small PEM helper module.

---

## Code-Level Comparison

### 1. PEM-to-JWK conversion

| | Human (`pem_to_jwks.lua`) | OpenSpec (`jwks.lua` internal) |
|---|---------------------------|--------------------------------|
| **Approach** | `pkey:tostring("public", "JWK")` | Same |
| **Lines** | ~25 | ~20 (inline in `jwks.lua`) |
| **pcall wrapping** | No | Yes (parse + export) |

Both use the correct OpenSSL primitive. OpenSpec’s `design.md` chose this path up front (no manual `n`/`e` extraction rabbit hole).

**Minor gap:** Human and Spec-Kit AI add `use = "sig"` on PEM-derived JWKs. OpenSpec output omits `use` in validated responses (not required by story, but a small interoperability difference).

### 2. Keyset path resolution

| | Human | OpenSpec |
|---|-------|----------|
| **Method** | `kong.request.get_uri_captures()` → `params.named.key_set` | `ngx.re.match` on `kong.request.get_path()` |
| **Config fallback** | Optional `key_set` in schema | None (zero config) |
| **Key iteration (filtered)** | `kong.db.keys:each_for_set({ id })` | `kong.db.keys:each()` + filter by `key_entity.set.id` |

OpenSpec did **not** use `kong.request.get_uri_captures()` despite `tasks.md` mentioning `kong.router.get_route()` / `ngx.ctx.router_matches`. The implemented `ngx.re.match` works for the validated routes but is a different PDK pattern than the human plugin.

### 3. Unknown / missing keyset

| | Human | OpenSpec |
|---|-------|----------|
| **Unknown keyset name** | HTTP **404** `{ message: "Key set not found" }` | HTTP **404** `{ message: "keyset not found: …" }` |

OpenSpec’s archived delta spec included a scenario for HTTP 200 + empty `keys` on unknown keyset; **implementation followed `tasks.md` (404)** instead. Behavior aligns with human plugin and Spec-Kit AI, not that delta scenario.

### 4. Schema and configuration

| | Human | OpenSpec |
|---|-------|----------|
| **Config** | Optional `key_set` string | Empty record (zero fields) |

OpenSpec matches the story’s “no configuration parameters.” Human’s optional `key_set` is more flexible for operators (see [comparison-report.md](./comparison-report.md) Issue 2).

### 5. Error handling

| Scenario | Human | OpenSpec |
|----------|-------|----------|
| `select_by_name` DB error | Not checked (nil only) | Returns **500** |
| Key iteration error | Logs, may return empty body | Logs warn, breaks loop |
| Bad PEM / JWK | Logs, skips key | Logs warn, skips key |
| Malformed stored JWK | Assumes decode succeeds | `cjson.safe` decode, skip with warn |

OpenSpec is more defensive on DB errors. Human has debug `kong.log.warn` on URI captures left in production code.

### 6. Response encoding

| | Human | OpenSpec |
|---|-------|----------|
| **Response** | `kong.response.exit(200, { keys = ... })` (table) | `kong.response.exit(200, cjson.encode(body), …)` (pre-encoded string) |

Both produce valid JSON in validation. OpenSpec’s pre-encoding is slightly non-idiomatic but functional.

---

## Scorecard

| Dimension | Human | OpenSpec AI | Notes |
|-----------|-------|-------------|-------|
| **PEM simplicity** | ✓ | ✓ | Same OpenSSL approach |
| **Spec/story compliance (zero config)** | Close | ✓ | |
| **Operational flexibility** | ✓ | — | Config `key_set` fallback |
| **Error handling** | — | ✓ | DB errors, pcall |
| **PDK idioms** | ✓ | Close | `get_uri_captures` + `each_for_set` vs regex + full scan |
| **Validation** | (baseline) | ✓ | curl checks passed |

**Overall:** OpenSpec produced a **working, maintainable** plugin with correct PEM strategy and passing local validation. Trade-offs: modular `jwks.lua` (good), full key scan for keyset filter (acceptable at scale), no `use: sig` on converted keys (minor), path capture via regex instead of URI captures (document in ops runbooks).

---

## Spec / Process Refinement Observations

### Issue 1: Delta spec vs implementation (unknown keyset) — resolved at archive

During propose, an intermediate delta draft used HTTP 200 + empty `keys` for an unknown keyset. **Implementation and `tasks.md` used 404**, matching the human and Spec-Kit plugins.

**After `/opsx:archive`:** `openspec/specs/jwks-endpoint/spec.md` requires **404** for a missing keyset (“Keyset not found” scenario). That matches `plugins/trust-registry-ai-openspec/` (`jwks.lua` returns 404). **No follow-up delta is required** for this ticket.

**Refinement for future runs:** Run `/opsx:verify` before archive to catch spec/code drift earlier.

### Issue 2: tasks.md PDK names vs what shipped

Tasks referenced `kong.router.get_route()` / `ngx.ctx.router_matches`; code uses `ngx.re.match` on path. Worked in validation but shows task artifact drift from implementation.

**Refinement:** Optional `/opsx:verify` or human review of tasks after apply.

### Issue 3: No tests in output

Neither OpenSpec `tasks.md` nor Spec-Kit constitution produced busted tests for this feature. Validation was manual (Docker + curl), which matched Spec-Kit’s interactive validation pattern.

**Refinement:** Add to `openspec/config.yaml` context: “Include busted unit test tasks for each acceptance scenario.”

### Comparison methodology (not an issue)

OpenSpec `/opsx:propose` used the **same story text** as Spec-Kit `/speckit-specify`, plus the `/speckit-plan`-equivalent naming line (`trust-registry-ai-openspec` in a separate plugin directory). No extra hints (e.g. “survey lua-resty-openssl”) were added beyond what Spec-Kit received. That keeps the workflow/cost/code comparison fair; only the tooling and phase count differ.

---

## Related

- [OpenSpec README](../../docs/openspec-readme.md)
- [Spec-Kit vs OpenSpec](./speckit-vs-openspec.md)
- [Human vs Spec-Kit AI](./comparison-report.md)
