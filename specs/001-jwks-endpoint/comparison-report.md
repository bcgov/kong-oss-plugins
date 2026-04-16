# Comparison Report: trust-registry (Human) vs trust-registry-ai (AI)

**Date**: 2026-04-16
**Scope**: Plugin code comparison + spec/plan/task refinement observations
**Spec**: `specs/001-jwks-endpoint/`

## Structure

Both plugins share identical file layouts:

```text
plugins/<name>/
├── kong-plugin-<name>-1.0.0-0.rockspec
└── src/
    ├── handler.lua
    ├── pem_to_jwk[s].lua
    └── schema.lua
```

---

## Code-Level Comparison

This section looks in detail at the code-level differences between the human and AI implementations.

You may want to skip this section and go straight to the [Spec / Plan / Task Refinement Observations](#spec--plan--task-refinement-observations) section which captures more meta-level observations about the process.

### 1. PEM-to-JWK Conversion (largest divergence)


|                | Human (`pem_to_jwks.lua`)                                     | AI (`pem_to_jwk.lua`)                                                              |
| -------------- | ------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| **Approach**   | Delegates to OpenSSL: `pkey:tostring("public", "JWK")`        | Manually extracts parameters (n, e / x, y), base64url encodes, assembles JWK table |
| **Lines**      | ~20                                                           | ~80                                                                                |
| **Key types**  | Any type OpenSSL supports                                     | RSA and EC only (with a hand-rolled curve map)                                     |
| **Robustness** | If OpenSSL adds Ed25519/Ed448 support, it works automatically | Would need new code paths for each key type                                        |


The human approach is significantly simpler and more future-proof. The AI built a manual extraction pipeline that reimplements what `resty.openssl.pkey` already provides via `:tostring()`. The CURVE_MAP + bit-size fallback + short-name refinement logic in the AI version is a textbook case of over-engineering.

**Root cause**: The research phase committed to a manual parameter-extraction approach (Decision 2 in `research.md`) without surveying the `resty.openssl.pkey` API for higher-level methods. The library's `:tostring("public", "JWK")` is publicly documented and would have been discoverable via the library's README or general LLM knowledge of `lua-resty-openssl`. Two contributing biases:

One contributing bias was that other plugins in the repo (`trust-sign`, `trust-hello`) use `get_parameters()` for *signing operations* where individual key components are needed. The AI mistakenly generalized that pattern to PEM→JWK serialization, which is a different problem (you want a serialized JWK, not its parts).
2. The `plugins/trust-registry/` denial removed the most direct signal ("here's the 5-line answer"), but the alternative was never truly hidden.

The deeper process gap: the spec-driven workflow has no "survey the relevant library's API surface before choosing an approach" step. Once Decision 2 was written into `research.md`, the plan and tasks built on it without revisiting whether a simpler primitive existed.

### 2. Schema and Configuration


|                    | Human                               | AI                         |
| ------------------ | ----------------------------------- | -------------------------- |
| **Config**         | Optional `key_set` string parameter | Empty config (zero fields) |
| **Spec alignment** | Deviates from FR-008 (zero config)  | Matches FR-008 exactly     |


The human version's optional `key_set` config is pragmatically useful: it lets operators bind a keyset at the plugin level without relying on route regex captures, allowing for serving keys for a keyset from the standard `/.well-known/jwks.json` URL. This is a case where FR-008 (zero config parameters) was arguably too rigid. In practice, having both a route-capture and a config-level fallback gives operators more deployment flexibility.

The human provided spec said "The Kong plugin does not *need* any configuration parameters" (emphasis added), which was translated into FR-008 during the specify step.

### 3. Route Parameter Extraction


|                              | Human                             | AI                                   |
| ---------------------------- | --------------------------------- | ------------------------------------ |
| **Method**                   | `kong.request.get_uri_captures()` | `kong.request.get_path():match(...)` |
| **Fallback**                 | Config `key_set` parameter        | None                                 |
| **Key set resolution order** | URI capture > config > all keys   | Path match > all keys                |


The AI's research recommended `kong.router.get_uri_captures()`, which doesn't exist in Kong 3.9. This was caught during validation and replaced with path matching. The human version uses `kong.request.get_uri_captures()` (the correct PDK method, subtly different from `kong.router.get_uri_captures()`).

The human version also has debug logging (`kong.log.warn("URI captures: ", ...)`) left in the handler — something that should be removed before production.

### 4. Error Handling


| Scenario                  | Human                                  | AI                                            |
| ------------------------- | -------------------------------------- | --------------------------------------------- |
| `select_by_name` DB error | Not checked (only checks `nil` result) | Checks `err`, returns 500                     |
| Key iteration error       | Returns `nil` (no HTTP response)       | Breaks loop, returns whatever was collected   |
| PEM conversion failure    | Logs error, skips key                  | Logs error, skips key                         |
| JWK decode failure        | Not handled (assumes success)          | Wrapped in `pcall`, logs and skips on failure |


The AI is more defensive here. The human version has a gap: if `kong.db.key_sets:select_by_name()` returns a DB error (not nil, but an actual error), it falls through silently. And on key iteration error, the handler returns nothing — the client gets an empty response or a Kong default error.

### 5. JWK Field Handling


|                          | Human                                       | AI                                        |
| ------------------------ | ------------------------------------------- | ----------------------------------------- |
| `kid` on JWK-format keys | Not set (uses whatever's in the stored JWK) | Overrides with `key.kid` from Kong entity |
| `use` field              | Adds `use = "sig"` on PEM-converted keys    | Not added                                 |


The AI's `kid` override is more correct per FR-005 ("each JWK MUST include the `kid` field matching the key's identifier in Kong"). If a stored JWK has a different `kid` than the Kong entity's `kid`, the human version would return the wrong one.

The human version's `use = "sig"` is not in the spec but is a reasonable real-world addition (keys in this system are for signature verification).

### 6. Other Differences


|                           | Human                                      | AI                                        |
| ------------------------- | ------------------------------------------ | ----------------------------------------- |
| **Priority**              | 940                                        | 1000                                      |
| **Rockspec `source.dir`** | `plugins/dpop/src` (copy-paste bug)        | `plugins/trust-registry-ai/src` (correct) |
| **Debug logging**         | `kong.log.warn` for URI captures (left in) | Error logging only                        |


---

## Scorecard


| Dimension             | Human  | AI              | Notes                                                              |
| --------------------- | ------ | --------------- | ------------------------------------------------------------------ |
| **Simplicity**        | Better | --              | PEM conversion is ~4x fewer lines                                  |
| **Extensibility**     | Better | --              | OpenSSL delegation handles future key types                        |
| **Error handling**    | --     | Better          | DB errors, JWK decode, iteration all covered                       |
| **Spec compliance**   | Close  | Slightly better | kid override, zero-config match FR-005/FR-008                      |
| **Practical utility** | Better | --              | Config fallback for key_set                                        |
| **Code hygiene**      | Tie    | Tie             | Human has debug logging left in; AI has over-engineered conversion |


**Overall**: The human plugin is more pragmatic and concise. The AI plugin is more spec-compliant and defensively coded. A best-of-both implementation would use the human's PEM conversion approach with the AI's error handling discipline.

---

## Spec / Plan / Task Refinement Observations

### Issue 1: Research commits to APIs without actually examining the library

**Where**: `research.md`, Decisions 2 and 4

The research step picked library APIs without checking the library. Two manifestations:

- **Decision 4** chose `kong.router.get_uri_captures()`, which doesn't exist in Kong 3.9. Caught during validation, not research.
- **Decision 2** picked a manual `get_parameters()` + base64url pipeline (~80 lines) without noticing that `resty.openssl.pkey:tostring("public", "JWK")` already does PEM→JWK in one call. The AI pattern-matched from `trust-sign`/`trust-hello`, which use `get_parameters()` for signing — a similar-looking but semantically different use case.

**Refinement**: Research decisions that touch external libraries should include an explicit API check:

- Pin a target version (e.g., "Kong Gateway 3.9.x", not just "3.x").
- Name the methods being used and confirm they exist at that version.
- Briefly survey alternatives: is there a higher-level primitive that collapses this?

This is cheap (minutes of doc reading) and catches both existence errors and over-engineering before they ship into `tasks.md`.

### Issue 2: Spec was too rigid on zero-config

**Where**: `spec.md`, FR-008

FR-008 mandates zero configuration, but the human version's optional `key_set` parameter is genuinely useful. It allows operators to scope a plugin instance to a keyset without relying on regex route captures. This is a common Kong pattern (configure behavior at the plugin level, not just the route level).

**Refinement**: The spec input described zero-config, but the specify step should have surfaced this as a trade-off: "FR-008 mandates zero config. However, an optional `key_set` config parameter would allow keyset binding without route-level regex captures. Confirm with owner." Specs should identify where zero-config simplicity conflicts with operational flexibility.

### Issue 3: No automated tests — three compounding causes

**Where**: `spec.md` (Success Criteria), `.specify/memory/constitution.md` (Principles II, IV), `tasks.md`

Three things combined to produce zero test artifacts:

1. **Spec input was silent on testing.** The `/speckit-specify` prompt described the feature but not how to verify it.
2. **Constitution actively forbids extras.** Principle II ("No Feature Expansion") and Principle IV ("minimum code required to satisfy the spec") classify any un-requested test as a violation. The AI was following the rules.
3. **Success criteria don't auto-translate.** SC-001–SC-004 describe measurable outcomes, but nothing in `/speckit-tasks` turns them into test tasks.

**Refinement (constitution level)**: Add a principle like "VIII. Verifiable by Default" — every acceptance scenario and success criterion MUST have at least one automated check, and tests are explicitly exempt from Principle II's "no extras" rule. Without this, the current constitution makes test-generation a rule violation.

**Refinement (template level)**: Once the constitution allows it, update `tasks-template.md` so `/speckit-tasks` emits one test task per acceptance scenario and per success criterion. Also add a consistency check: if `plan.md` names a test framework (this one declared `busted`) but `tasks.md` emits zero test tasks, flag it.

**Not the right fix**: putting "remember to ask for tests" in the `/speckit-specify` prompt — fragile, per-feature, and mixes spec authoring with verification strategy.

### Issue 4: "Did Claude cheat?" — search leakage

**Where**: `docs/spec-driven-development.md`

During the plan step, Claude searched for `pem_to_jwks` across `plugins/` and found files in `trust-registry/`. The constitution and Claude settings said not to read that directory, but *search results revealing file names and paths* still leaked structural information. The AI knew a `pem_to_jwks` module existed in the reference plugin even if it couldn't read its contents.

**Refinement**: If the goal is a clean-room implementation, the deny rule should cover search/glob, not just reads. Alternatively, accept that search-level awareness is fine (a human would know the file exists too) and focus the constraint on "must not copy implementation details."

### Issue 5: Task granularity for the handler

**Where**: `tasks.md`, T005 and T006

T005 (handler US1) packs iteration, JWK detection, PEM conversion dispatch, error logging, response building, and Content-Type headers into a single task. T006 then modifies that same file. These are large units of work that make it hard to checkpoint progress or isolate failures.

**Refinement**: For handler-heavy plugins, consider splitting by concern: "T005a: Implement key iteration and JWK assembly loop. T005b: Wire up response formatting and Content-Type. T005c: Add error logging for unconvertible keys." Smaller tasks are easier to validate and less likely to produce monolithic commits.

