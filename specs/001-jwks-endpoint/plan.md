# Implementation Plan: JWKS Endpoint

**Branch**: `001-jwks-endpoint` | **Date**: 2026-04-15 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/001-jwks-endpoint/spec.md`

## Summary

Implement a Kong plugin (`trust-registry-ai`) that serves a JSON Web
Key Set (JWKS) endpoint, exposing Kong's registered public keys in
RFC 7517 format. The plugin responds to two routes: one returning all
keys and one filtering by keyset name. Keys stored as PEM are
converted to JWK format; keys stored as JWK are returned as-is.

## Technical Context

**Language/Version**: Lua (LuaJIT, Kong plugin)
**Primary Dependencies**: Kong PDK, resty.openssl.pkey, cjson
**Storage**: Kong built-in key/key_set entities (via `kong.db`)
**Testing**: busted (Kong plugin testing framework)
**Target Platform**: Kong Gateway 3.x (OpenResty/nginx)
**Project Type**: Kong gateway plugin
**Performance Goals**: Standard Kong plugin response latency
**Constraints**: Read-only access to Kong key store; no upstream proxy
**Scale/Scope**: Single plugin, 3 source files

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Gate | Status |
| --------- | ---- | ------ |
| I. Specification Supremacy | All implementation traces to spec FR-001–FR-011 | PASS |
| II. No Feature Expansion | Plugin implements only JWKS serving; no extras | PASS |
| III. Deterministic Generation | Structure follows Kong conventions; no AI choices | PASS |
| IV. Repeatability & Minimality | 3 files, explicit termination per FR | PASS |
| V. Explicit Ambiguity | Plugin name clarified by owner (`trust-registry-ai`) | PASS |
| VI. No Hidden State | All state in filesystem and git | PASS |
| VII. Kong Convention Adherence | handler.lua, schema.lua, rockspec pattern | PASS |
| Excluded Source | `plugins/trust-registry/` not referenced | PASS |

## Project Structure

### Documentation (this feature)

```text
specs/001-jwks-endpoint/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── jwks-api.md
└── tasks.md            (created by /speckit-tasks)
```

### Source Code (repository root)

```text
plugins/trust-registry-ai/
├── src/
│   ├── handler.lua      # Access phase: read keys, build JWKS, respond
│   ├── schema.lua       # Zero-config schema (empty fields)
│   └── pem_to_jwk.lua   # PEM-to-JWK conversion (RSA, EC)
└── kong-plugin-trust-registry-ai-1.0.0-0.rockspec
```

**Structure Decision**: Standard Kong plugin layout following the
pattern established by trust-hello, trust-sign, and other plugins in
this repository. A separate `pem_to_jwk.lua` module isolates
conversion logic from the handler, following the trust-sign pattern
of dedicated utility modules.

## File-to-Requirement Mapping

| File | Spec Requirements |
| ---- | ----------------- |
| handler.lua | FR-001, FR-002, FR-004, FR-005, FR-007, FR-009, FR-010, FR-011 |
| schema.lua | FR-008 |
| pem_to_jwk.lua | FR-006 |
| rockspec | (build/packaging) |
| All response output | FR-003 (RFC 7517 compliance) |

## Key Technical Decisions

Documented in [research.md](research.md):

1. **Plugin name**: `trust-registry-ai` (owner-specified)
2. **PEM-to-JWK**: Self-contained module using `resty.openssl.pkey`.
   **Amended 2026-04-20 (FR-012)**: conversion delegates to
   `pkey:tostring("public", "JWK")` rather than extracting RSA/EC
   parameters by hand. The module still exposes the
   `pem_to_jwk(pem_string, kid)` signature returning a JWK table,
   but its body collapses from ~80 lines to ~20 and picks up any
   key type OpenSSL can serialize as JWK (not just RSA/EC). See
   `research.md` Decision 2 and the spec's Amendments section.
3. **DB access**: `kong.db.keys` and `kong.db.key_sets` DAO
4. **Route captures**: `kong.router.get_uri_captures()` for keyset
   path parameter
5. **Zero-config**: Empty `config.fields = {}` in schema
6. **Short-circuit**: `kong.response.exit()` in access phase

## Complexity Tracking

No constitution violations to justify. All gates pass.

## Amendments

### 2026-04-21 — Constitution v1.2 compliance (Principles VIII & IX)

Constitution v1.2 adds Principle VIII ("Verifiable by Default") and
Principle IX ("Proportional Test Coverage"). Both were absent at the
time this plan was authored, so the original Constitution Check block
above does not evaluate them. This amendment records the revised
Testing strategy, the additional gate results, and one correction to
Key Technical Decisions. The shipped code is NOT changing; only the
plan's test strategy and the task list's verification phase are being
added. See `comparison-report.md` Issue 3 for the background.

**Revised Testing field**: dual harness.

- Unit: `busted`. Specs live under `plugins/trust-registry-ai/spec/`.
  Added to the plugin rockspec as a test dependency.
- Integration: existing Playwright testsuite at `testsuite/`. New
  spec file at
  `testsuite/tests/plugins/trust-registry-ai/default.spec.ts` using
  the `provisionNewService` helper in `testsuite/helpers/kong.ts` and
  the docker-compose stack already in place.

Rationale: the integration harness is pre-existing (already used by
`oidc`, `jwt-keycloak`, and `response-signer`), so reusing it is the
minimal choice under Principle IV. `busted` covers Principle IX
unit-test triggers on `pem_to_jwk.lua` (parsing/transformation plus
reusable helper) without requiring a running Kong.

**Constitution Check addendum**:

| Principle | Gate | Status |
| --------- | ---- | ------ |
| VIII. Verifiable by Default | Every AS in `spec.md` (US1-AS1..3, US2-AS1..3) and every SC (SC-001..SC-004) has a test task in `tasks.md` Phase 6 with a `[Verifies: ...]` tag | PASS after Phase 6 is appended and implemented |
| IX. Proportional Test Coverage | `pem_to_jwk.lua` meets triggers (parsing/transformation, reusable helper) → unit spec planned. `handler.lua` error-handling paths per FR-011 are covered by integration tests (handler is Kong-coupled; unit-testing it in isolation would require mocking Kong PDK surface and is rejected as disproportionate per Principle IV) | PASS after Phase 6 is appended and implemented |

**Correction to Key Technical Decisions**:

Decision 4 above names `kong.router.get_uri_captures()` as the route
capture mechanism. That function does not exist in Kong Gateway 3.x;
the shipped handler uses `kong.request.get_path():match(...)` against
the known route pattern. This drift was identified in
`comparison-report.md` (Issue 1) and is corrected here for accuracy.
No code change is required — the shipped implementation is already
correct; only the plan's recorded decision needed updating.

These amendments do not alter any existing functional requirement or
acceptance scenario. They extend the verification strategy to match
Constitution v1.2 and correct one historical recording error in the
plan.
