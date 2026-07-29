---
name: reverse-spec
description: Reverse engineer an OpenSpec-style behavioral spec from an existing Kong plugin implementation, plus a coverage map for review. Use when the user asks to reverse-spec a plugin, generate a spec/requirements/scenarios from plugin code, or prepare a spec as the basis for spec-driven test generation.
---

Reverse engineer a behavioral spec from an existing Kong plugin implementation.

The spec documents behavior that **already exists**, so it is written directly to main specs (`openspec/specs/`), not to a change. The downstream test work is what becomes an OpenSpec change/delta. The spec will be used for **clean-room test generation** (a fresh agent session with only the spec and test standards in context), so it must be self-contained: a reader must be able to write tests from it without opening the plugin code.

**Input**: a plugin name (e.g. `trust-sign`). Source lives at `plugins/<plugin-name>/src/`. If the user provides supporting documentation (README, Jira, design docs), read it too.

**Outputs** (both produced in one run):

1. `openspec/specs/<plugin-name>/spec.md` — the normative spec
2. `openspec/specs/<plugin-name>/coverage.md` — review aid mapping surfaces to requirements; NOT normative, never read during test generation

## Steps

1. **Read the implementation**

   Read every file in `plugins/<plugin-name>/src/` — handler phases (access, header_filter, body_filter, etc.), `schema.lua`, and all helper modules. Check the rockspec for the module list. Read supporting docs if provided.

2. **Enumerate input/output surfaces**

   Build a working list before drafting any requirements. Be systematic — the non-obvious surfaces are the ones that get missed:

   - **Inputs**: plugin config fields (including schema constraints: required, `one_of`, defaults), request/response headers and bodies, Kong entities (e.g. service/route **tags**), environment variables (`os.getenv`), upstream response status/source
   - **Outputs**: headers set/removed, status codes / early exits, token or claim contents, body modifications

3. **Draft requirements and scenarios**

   Group observable behavior into Requirements, each with one or more Scenarios (see format below). Every surface from step 2 must end up either in a requirement or in the Out of scope section.

4. **Write the spec** to `openspec/specs/<plugin-name>/spec.md` using the structure below.

5. **Write the coverage map** to `openspec/specs/<plugin-name>/coverage.md`. Every enumerated surface gets a row with a disposition (requirement name or "out of scope"). **Warn loudly in your summary if any surface has no disposition** — that is a spec gap.

6. **Validate**: run `openspec validate --specs` and fix any structural errors.

## Spec structure

```markdown
# <plugin-name> Specification

## Purpose
[2-3 sentences: what the plugin does and where it sits in the request/response flow]

## Requirements

### Requirement: <Behavior name>
**ID**: `<plugin-name>.<requirement-slug>`

The plugin SHALL <observable behavior>.

#### Scenario: <case name>
**ID**: `<plugin-name>.<requirement-slug>.<scenario-slug>`
- **TAG**: quirk — <one-line why>   <!-- only when quirk; omit otherwise -->
- **WHEN** <input condition>
- **THEN** <observable outcome>

## Interop / shared contract   <!-- only for interdependent plugins -->

## Out of scope                <!-- only if non-trivial -->
- <one bullet per dead/commented-out or documented-but-unimplemented feature>
```

Keep it complete but short and reviewable — not a code walkthrough. Every requirement needs at least one scenario.

### Stable IDs (required)

Every Requirement and Scenario MUST have a stable `**ID**` so clean-room test
generation can cite `[Verifies: <id>]` and prove completion without fuzzy
title matching. Titles remain the human-readable label.

- Requirement ID: `<plugin-name>.<requirement-slug>`
- Scenario ID: `<requirement-id>.<scenario-slug>`
- Slugs: lowercase kebab-case derived from the title
- Order under a Scenario heading: `**ID**`, then optional `**TAG**`, then `WHEN`/`THEN`
- IDs are stable once published — renaming is a migration, not a drive-by edit

Example: Requirement "Direction gating" → `trust-sign.direction-gating`;
Scenario "Direction unset is a no-op" → `trust-sign.direction-gating.unset-noop`.

## Rules

**Spec observable behavior only** — headers, status codes, claims, config schema effects. Do NOT encode internals: module names, `PRIORITY`, cache TTLs, log message text.

**Config schema is in scope.** Required fields, `one_of` constraints, and defaults are observable and testable. Also spec what happens on meaningful config branches (e.g. a field unset making the plugin a no-op).

**Scenario tagging** — after `**ID**`, the first bullet may be a tag:

- **Contract** (untagged, the default): desired behavior = as-implemented; tests will hard-assert.
- **Quirk**: `- **TAG**: quirk — <one-line why>` — odd or suspect as-implemented behavior. Document current behavior faithfully (tests still hard-assert); the tag flags it for peer review. Use when multiple plugins must agree on the odd behavior, or changing it is a product/security decision. Tag and keep going — do NOT stop to triage bugs during spec generation.
- **Pending**: `- **TAG**: pending — <ticket-key>` — reserved for peer review (**Replace later**). **Never emit this tag during reverse-spec generation.**

Peer review of quirks (not done by this skill; for reviewer context):

1. **Keep** — assert as-implemented; drop `quirk` if promoting to contract
2. **Fix now** — land a small plugin change, rewrite the scenario to desired behaviour as untagged contract (no `pending` / xfail)
3. **Replace later** — file a bug → rewrite scenario to desired → `- **TAG**: pending — <ticket>` (tests will xfail until fixed)
4. **Defer** (rare) — leave quirk-tagged if review can’t decide

Example quirk scenario:

```markdown
#### Scenario: Empty response body gets no digest
**ID**: `trust-sign.response-digest-generation.empty-response-body-no-digest`
- **TAG**: quirk — asymmetric with request path, which digests empty bodies
- **WHEN** the upstream response body is an empty string and Content-Digest is absent
- **THEN** no Content-Digest header is added to the response
```

**Interdependent plugins** (e.g. `trust-verify-signature` consumes what `trust-sign` produces):

- Create a separate capability spec per plugin; spec the **producer first**, then the consumer.
- Capture the shared wire format (header names, token structure, claims) in a short `## Interop / shared contract` section in **both** specs.
- The producer spec is the **source of truth** for the shared contract; the consumer spec states this explicitly and mirrors only what it depends on.
- When generating the **consumer** spec, reference the producer's **spec, not its code**:
  - Derive the consumer's own requirements from the consumer's code, as usual.
  - Mirror into the consumer's Interop section only the subset of the producer spec's contract that the consumer code actually depends on.
  - If the consumer code depends on something **missing from or contradicting** the producer spec's contract, do not invent it and do not read producer code to resolve it — tag the affected scenario `quirk` with the mismatch as the reason, and report it in the summary. It is either a producer-spec gap or a real interop bug; peer review decides which.

**Out of scope section**: one bullet per item for dead/commented-out code or features documented elsewhere (Jira, README) but not fully implemented. If trivial, omit the section entirely.

## Coverage map format

```markdown
# <plugin-name> coverage map

> Review aid only — not normative. Clean-room test generation uses spec.md alone.

| Surface | Kind | Disposition |
|---|---|---|
| `config.direction` | config | Requirement: Direction gating |
| `Content-Digest` request header | input | Requirement: Request digest generation |
| `KONG_SIGNING_CERT_KEY` env var | input | Requirement: Private key resolution |
| commented-out Signature-Input code | dead code | Out of scope |
| `X-Edge-Token` request header | input | ⚠️ GAP — no requirement or out-of-scope |
```

A blank or `⚠️ GAP` disposition is a **spec gap**. Call it out in the summary so it is visible for peer review — leave it for reviewers to resolve.

## Summary output

After both files are written and validation passes, report:

- Paths of `spec.md` and `coverage.md`
- Requirement and scenario counts (and confirm every requirement/scenario has an `**ID**`)
- Quirk-tagged scenarios (list them with IDs — these are the peer-review focal points)
- Any surfaces without a disposition (spec gaps — resolve in this run or during review)
