# Tasks: JWKS Endpoint

**Input**: Design documents from `specs/001-jwks-endpoint/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

## Format: `[ID] [P?] [Story] [Verifies?] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- **[Verifies]**: Required on every test task (Phase 6 and later). Cites
  the acceptance scenario ID (e.g., `US1-AS2`) and/or Success Criterion
  ID (e.g., `SC-003`) the test verifies. A single test MAY verify
  multiple IDs.
- Include exact file paths in descriptions

## Phase 1: Setup

**Purpose**: Create the plugin directory structure and build configuration.

- [x] T001 Create plugin directory structure at `plugins/trust-registry-ai/src/`
- [x] T002 Create rockspec at `plugins/trust-registry-ai/kong-plugin-trust-registry-ai-1.0.0-0.rockspec` with modules: handler, schema, pem_to_jwk (FR-008, build/packaging)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core modules that MUST be complete before user story implementation.

- [x] T003 [P] Create zero-config schema at `plugins/trust-registry-ai/src/schema.lua` with name `trust-registry-ai`, `protocols = typedefs.protocols_http`, and empty `config.fields = {}` (FR-008)
- [x] T004 [P] Create PEM-to-JWK conversion module at `plugins/trust-registry-ai/src/pem_to_jwk.lua` using `resty.openssl.pkey`: load PEM, detect key type (RSA/EC), extract parameters (RSA: n,e; EC: x,y,crv), base64url-encode, return JWK table with kty and kid (FR-006)

**Checkpoint**: Schema and conversion module ready. Handler implementation can begin.

---

## Phase 3: User Story 1 - Retrieve All Public Keys (Priority: P1)

**Goal**: Serve a JWKS document at `GET /.well-known/jwks.json` containing all registered keys.

**Independent Test**: Register keys via Kong Admin API (JWK and PEM formats), send `GET /.well-known/jwks.json`, verify response is a valid JWKS with all keys present.

### Implementation for User Story 1

- [x] T005 [US1] Implement handler access phase at `plugins/trust-registry-ai/src/handler.lua`: iterate `kong.db.keys:each()`, for each key use `cjson.decode(key.jwk)` if JWK present or call `pem_to_jwk` module if only PEM, log and skip keys that fail conversion (FR-011), build `{keys = [...]}` response, return via `kong.response.exit(200, body, {["Content-Type"] = "application/json"})`. Return empty `{keys = {}}` when no keys exist (FR-001, FR-003, FR-004, FR-005, FR-007, FR-010, FR-011)

**Checkpoint**: `GET /.well-known/jwks.json` returns a complete JWKS document. MVP is functional.

---

## Phase 4: User Story 2 - Retrieve Keys by Keyset (Priority: P2)

**Goal**: Filter JWKS response by keyset name via `GET /keysets/{key_set}/.well-known/jwks.json`.

**Independent Test**: Register keys in a named keyset, send `GET /keysets/{name}/.well-known/jwks.json`, verify only that keyset's keys are returned. Send request for nonexistent keyset, verify 404.

### Implementation for User Story 2

- [x] T006 [US2] Add keyset filtering to handler access phase at `plugins/trust-registry-ai/src/handler.lua`: use `kong.router.get_uri_captures()` to extract `key_set` named capture, if present call `kong.db.key_sets:select_by_name(key_set)` and return 404 `{message = "Key set not found"}` if nil (FR-009), otherwise iterate `kong.db.keys:each_for_set({id = kset.id})` using same JWK conversion logic from US1 (FR-002)

**Checkpoint**: Both routes functional. Keyset filtering returns scoped results. Nonexistent keyset returns 404.

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Validate the complete implementation against quickstart scenarios.

- [x] T007 Run quickstart.md validation at `specs/001-jwks-endpoint/quickstart.md`: verify all 5 validation checkboxes pass against a running Kong instance

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on T001 (directory must exist) — BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on T003 and T004 (schema and conversion module)
- **User Story 2 (Phase 4)**: Depends on T005 (extends handler from US1)
- **Polish (Phase 5)**: Depends on T006 (all stories complete)

### Within Each Phase

- T003 and T004 are independent and can run in parallel [P]
- T005 requires both T003 and T004 to be complete
- T006 modifies T005's output (same file, sequential)

### Parallel Opportunities

```text
After T001:
  T002 (rockspec)  |  T003 (schema)  |  T004 (pem_to_jwk)
  ─────────────────────────────────────────────────────────
After T003 + T004:
  T005 (handler US1)
  ─────────────────
After T005:
  T006 (handler US2)
  ─────────────────
After T006:
  T007 (validation)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001)
2. Complete Phase 2: Foundational (T002, T003, T004 in parallel)
3. Complete Phase 3: User Story 1 (T005)
4. **STOP and VALIDATE**: `GET /.well-known/jwks.json` works
5. Deploy/demo if ready

### Full Delivery

1. Setup + Foundational → Plugin skeleton ready
2. User Story 1 → All-keys endpoint functional (MVP)
3. User Story 2 → Keyset filtering added
4. Polish → Quickstart validation passes

---

## Phase 6: Verification Backfill (Constitution v1.2 — Principles VIII & IX)

**Purpose**: Retrofit automated verification onto the shipped plugin so
every acceptance scenario and Success Criterion in `spec.md` has at
least one automated check. Source code is NOT changed by this phase —
only test files and test configuration.

**Prerequisites**:

- plan.md Amendments section dated 2026-04-21 in place (declares dual
  harness).
- `busted` added as a test dependency in
  `plugins/trust-registry-ai/kong-plugin-trust-registry-ai-1.0.0-0.rockspec`.
- Playwright `testsuite/` stack is already runnable (it is).

**Gate rule for this phase**: All tests MUST be written first and MUST
fail against a clean checkout before any remediation. Because the
plugin is already shipped, "fail first" here means: if a test passes
immediately, confirm it's actually exercising the intended path
(no false green). If a test fails, that's diagnostic input — file a
spec amendment or code fix separately; do not silently alter tests to
match buggy behavior.

### Setup for Phase 6

- [x] T008 Add `busted` (and any transitive test-only deps) to
  `test_dependencies` in
  `plugins/trust-registry-ai/kong-plugin-trust-registry-ai-1.0.0-0.rockspec`.
  Create empty `plugins/trust-registry-ai/spec/` directory with a
  `.gitkeep`.

### Unit Tests (Principle IX)

- [x] T009 [P] [Verifies: FR-006, FR-012, FR-013] Busted unit spec at
  `plugins/trust-registry-ai/spec/pem_to_jwk_spec.lua`. Cover:
  (a) RSA PEM → JWK has expected `kty`, `n`, `e`, and the supplied
  `kid`;
  (b) EC PEM → JWK has expected `kty`, `crv`, `x`, `y`, and `kid`;
  (c) invalid/malformed PEM returns `nil` plus a non-empty error
  string (not a raised exception);
  (d) FR-013 boundary: `pem_to_jwk` itself does NOT set `use`
  (`use = "sig"` is injected by the handler, per the shipped code);
  the unit test pins the module's contract so a future refactor that
  moves `use` into `pem_to_jwk.lua` must be accompanied by an
  explicit spec update.

### Integration Tests (Principle VIII — one per acceptance scenario)

All integration tasks live in a new spec file
`testsuite/tests/plugins/trust-registry-ai/default.spec.ts`,
provisioning service + route + plugin via
`testsuite/helpers/kong.ts::provisionNewService` (or a plugin-specific
helper extending it if routes for this plugin need the
`/.well-known/jwks.json` and `/keysets/{name}/.well-known/jwks.json`
path shapes, which they do — see test harness note below).

**Test harness note**: `provisionNewService` currently builds routes
with a generated numeric path prefix (`/NNNNNNNN`). JWKS routes require
specific path patterns. Expect T010 to introduce a small
`provisionJwksRoutes` helper (in
`testsuite/helpers/kong.ts` or a new
`testsuite/helpers/trust-registry-ai.ts`) that provisions two routes
per test run: one for `GET /.well-known/jwks.json` and one for
`GET /keysets/(?<key_set>[^/]+)/.well-known/jwks.json`, plus admin-API
fixtures for registering keys and keysets. This helper is test
infrastructure, not product code.

- [x] T010 [US1] [Verifies: US1-AS1, SC-001] Integration test: register
  N keys in Kong (mix of JWK and PEM), `GET /.well-known/jwks.json`,
  assert HTTP 200, `Content-Type: application/json`, response body
  has `keys` array of length N, every registered `kid` is present
  exactly once. SC-001 is covered by the count assertion.

- [x] T011 [US1] [Verifies: US1-AS2, SC-003] Integration test: register
  a PEM-only key, `GET /.well-known/jwks.json`, assert the returned
  JWK has the correct `kid`, `kty ∈ {"RSA","EC"}`, `use = "sig"`, and
  (for SC-003) the overall response body validates against an RFC 7517
  JWKS JSON schema (use an off-the-shelf JWKS schema fixture in
  `testsuite/`; add if missing).

- [ ] T012 [US1] [Verifies: US1-AS3, FR-010] Integration test: with
  no keys registered in Kong, `GET /.well-known/jwks.json` returns
  HTTP 200 with body `{"keys": []}`.

- [x] T013 [US2] [Verifies: US2-AS1, SC-002] Integration test: create a
  keyset named `signing` with exactly two keys; create a second keyset
  `other` with one key; `GET /keysets/signing/.well-known/jwks.json`
  returns HTTP 200 and exactly the two keys from `signing`, no
  others (SC-002 false-positive / omission check).

- [ ] T014 [US2] [Verifies: US2-AS2] Integration test: create empty
  keyset `empty`, `GET /keysets/empty/.well-known/jwks.json` returns
  HTTP 200 with body `{"keys": []}`.

- [x] T015 [US2] [Verifies: US2-AS3, FR-009] Integration test:
  `GET /keysets/nonexistent/.well-known/jwks.json` returns HTTP 404
  with a JSON body containing a `message` field.

- [x] T016 [US1] [Verifies: FR-011] Integration test: register a key
  with PEM content that cannot be parsed by OpenSSL (e.g., truncated
  PEM), plus one valid key; `GET /.well-known/jwks.json` returns HTTP
  200 with only the valid key in `keys`; confirm Kong's error log
  contains the expected `trust-registry-ai: failed to convert PEM to
  JWK` message (tail the kong container log or use an admin endpoint
  if available in the testsuite). This is FR-011's spec-mandated
  error path and is the Principle IX trigger that could not be
  unit-tested against the Kong-coupled handler.

### Success Criterion SC-004 (end-to-end signature verification)

- [x] T017 [Verifies: SC-004] Integration test: generate an RSA key
  pair in the test (node `jose` or `crypto.generateKeyPairSync`),
  register the public key in Kong as a PEM-format key, sign a JWS
  (compact serialization) over a known payload using the private key,
  `GET /.well-known/jwks.json`, look up the JWK by `kid`, verify the
  JWS signature against the returned JWK. Test passes only if
  verification succeeds. This exercises the full
  sign → publish → fetch → verify loop that SC-004 demands.

### Phase 6 Gate (mechanical checks before Phase 6 is considered done)

- [x] T018 Traceability check: every AS ID (US1-AS1, US1-AS2, US1-AS3,
  US2-AS1, US2-AS2, US2-AS3) appears in at least one `[Verifies: ...]`
  tag in this file. Every SC ID (SC-001, SC-002, SC-003, SC-004)
  appears in at least one `[Verifies: ...]` tag. Both busted and
  Playwright are actually invoked by at least one task above.
  (Currently verifiable by grepping this file.)

---

## Amendments

### 2026-04-21 — Phase 6 added (Constitution v1.2 compliance)

Phase 6 was added after original shipping of the plugin to bring the
feature into compliance with Constitution v1.2 Principles VIII and IX.
T001–T007 are unchanged. See plan.md Amendments section of the same
date for harness selection rationale.

---

## Notes

- [P] tasks = different files, no dependencies
- [US*] label maps task to specific user story for traceability
- [Verifies] is REQUIRED on every test task (Phase 6 onward) per
  Constitution Principle VIII. Originally omitted because tests were
  not generated under Constitution v1.1.
- Each user story is independently completable and testable
- Commit after each task or logical group
