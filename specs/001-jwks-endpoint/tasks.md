# Tasks: JWKS Endpoint

**Input**: Design documents from `specs/001-jwks-endpoint/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- Include exact file paths in descriptions

## Phase 1: Setup

**Purpose**: Create the plugin directory structure and build configuration.

- [ ] T001 Create plugin directory structure at `plugins/trust-registry-ai/src/`
- [ ] T002 Create rockspec at `plugins/trust-registry-ai/kong-plugin-trust-registry-ai-1.0.0-0.rockspec` with modules: handler, schema, pem_to_jwk (FR-008, build/packaging)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core modules that MUST be complete before user story implementation.

- [ ] T003 [P] Create zero-config schema at `plugins/trust-registry-ai/src/schema.lua` with name `trust-registry-ai`, `protocols = typedefs.protocols_http`, and empty `config.fields = {}` (FR-008)
- [ ] T004 [P] Create PEM-to-JWK conversion module at `plugins/trust-registry-ai/src/pem_to_jwk.lua` using `resty.openssl.pkey`: load PEM, detect key type (RSA/EC), extract parameters (RSA: n,e; EC: x,y,crv), base64url-encode, return JWK table with kty and kid (FR-006)

**Checkpoint**: Schema and conversion module ready. Handler implementation can begin.

---

## Phase 3: User Story 1 - Retrieve All Public Keys (Priority: P1)

**Goal**: Serve a JWKS document at `GET /.well-known/jwks.json` containing all registered keys.

**Independent Test**: Register keys via Kong Admin API (JWK and PEM formats), send `GET /.well-known/jwks.json`, verify response is a valid JWKS with all keys present.

### Implementation for User Story 1

- [ ] T005 [US1] Implement handler access phase at `plugins/trust-registry-ai/src/handler.lua`: iterate `kong.db.keys:each()`, for each key use `cjson.decode(key.jwk)` if JWK present or call `pem_to_jwk` module if only PEM, log and skip keys that fail conversion (FR-011), build `{keys = [...]}` response, return via `kong.response.exit(200, body, {["Content-Type"] = "application/json"})`. Return empty `{keys = {}}` when no keys exist (FR-001, FR-003, FR-004, FR-005, FR-007, FR-010, FR-011)

**Checkpoint**: `GET /.well-known/jwks.json` returns a complete JWKS document. MVP is functional.

---

## Phase 4: User Story 2 - Retrieve Keys by Keyset (Priority: P2)

**Goal**: Filter JWKS response by keyset name via `GET /keysets/{key_set}/.well-known/jwks.json`.

**Independent Test**: Register keys in a named keyset, send `GET /keysets/{name}/.well-known/jwks.json`, verify only that keyset's keys are returned. Send request for nonexistent keyset, verify 404.

### Implementation for User Story 2

- [ ] T006 [US2] Add keyset filtering to handler access phase at `plugins/trust-registry-ai/src/handler.lua`: use `kong.router.get_uri_captures()` to extract `key_set` named capture, if present call `kong.db.key_sets:select_by_name(key_set)` and return 404 `{message = "Key set not found"}` if nil (FR-009), otherwise iterate `kong.db.keys:each_for_set({id = kset.id})` using same JWK conversion logic from US1 (FR-002)

**Checkpoint**: Both routes functional. Keyset filtering returns scoped results. Nonexistent keyset returns 404.

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Validate the complete implementation against quickstart scenarios.

- [ ] T007 Run quickstart.md validation at `specs/001-jwks-endpoint/quickstart.md`: verify all 5 validation checkboxes pass against a running Kong instance

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

## Notes

- [P] tasks = different files, no dependencies
- [US*] label maps task to specific user story for traceability
- No test tasks generated (not requested in specification)
- Each user story is independently completable and testable
- Commit after each task or logical group
