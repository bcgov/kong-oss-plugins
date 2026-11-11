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

3. **Second pass**

   Re-read the handler(s) with the surface list in hand. Ask only:
   - Same logical operation on more than one path? Do the paths agree on
     the observable steps, or does one omit/alter something?
   - Control-flow branches the code actually takes (including fall-through)
     that have no candidate scenario yet?
   - Handler assumptions that disagree with the schema?

   Add hits to the working list (scenario candidate, `quirk` candidate, or
   Out of scope). Skip silently = miss.

4. **Draft requirements and scenarios**

   Group observable behavior into Requirements, each with one or more Scenarios (see format below). Every surface from steps 2–3 must end up either in a requirement or in the Out of scope section.

5. **Write the spec** to `openspec/specs/<plugin-name>/spec.md` using the structure below.

6. **Write the coverage map** to `openspec/specs/<plugin-name>/coverage.md`. Every enumerated surface gets a row with a disposition (requirement name or "out of scope"). **Warn loudly in your summary if any surface has no disposition** — that is a spec gap.

7. **Testability check** — for each scenario, confirm WHEN/THEN is unambiguous and testable without reading plugin source. Add a missing seam line when an export already exists; flag the rest. See **Testability** below.

8. **Validate**: run `openspec validate --specs` and fix any structural errors.

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

Keep it complete and reviewable — not a code walkthrough. Prefer more scenarios over OR'd WHENs when branches need their own tests (see **One WHEN per scenario** below). Every requirement needs at least one scenario.

### Stable IDs (required)

Every Requirement and Scenario MUST have a stable `**ID**`. Requirement IDs are
structural (grouping + seam attachment). Scenario IDs are what clean-room test
generation cites as `[Verifies: <scenario-id>]` to prove completion without
fuzzy title matching. Titles remain the human-readable label.

- Requirement ID: `<plugin-name>.<requirement-slug>`
- Scenario ID: `<requirement-id>.<scenario-slug>`
- Slugs: lowercase kebab-case derived from the title
- Order under a Scenario heading: `**ID**`, then optional `**TAG**`, then `WHEN`/`THEN`
- IDs are stable once published — renaming is a migration, not a drive-by edit

Example: Requirement "Direction gating" → `trust-sign.direction-gating`;
Scenario "Direction unset is a no-op" → `trust-sign.direction-gating.unset-noop`.

## Rules

**Spec observable behavior only** — headers, status codes, claims, config schema effects. Do NOT encode internals: `PRIORITY`, cache TTLs, log message text, or module layout walkthroughs.

**Unit-test seams** (exception — short, rare): when a scenario is **not** practical to assert on the wire (e.g. process-global env resolution) and the implementation already exports a pure/helper function for it, add **one sentence** to that requirement’s prose:

> Unit tests MAY call `<export>` (`require "<module>"`).

Use the short module name only (`sign`, `digest`) — do **not** put `package.path` or filesystem paths in the spec (busted harness uses cwd `plugins/<plugin>/` + `./src/?.lua`). Do **not** invent seams for wire-observable behavior, and do **not** list every export — only when clean-room busted would otherwise have no named subject under test. Add the line during the **Testability** check when the export already exists.

**Config schema is in scope**, but describe it fully while scenario-ing it sparingly. A clean-room test author cannot open `schema.lua`, so the Configuration schema requirement's prose MUST state every field, its type, whether it is required, its `one_of` values, and its default — that is how they construct valid configs for every other scenario.

Scenarios are what become mandatory tests, so emit them only where the plugin contributes logic:

- **One roll-up scenario** for required fields, and **one** for enumerated (`one_of`) fields. Do not emit one per field — asserting a bare `required = true` only re-tests Kong's validator.
- **One scenario per plugin-authored validation rule**: `entity_checks` (`only_one_of`, `at_least_one_of`, `mutually_required`, `conditional`), `custom_validator` functions, and `match` patterns. These are real branching logic and are easy to get subtly wrong.
- **One scenario** for a canonical valid config being accepted.

Also spec what happens on meaningful config branches (e.g. a field unset making the plugin a no-op). Watch for schema/handler disagreement while reading — a field the handler requires but the schema does not (or vice versa) is a `quirk`, and no schema test will catch it, so the spec is the only place it surfaces.

**One WHEN per scenario** — clean-room test generation gates completion on scenario IDs (`[Verifies: <id>]`), not on English disjuncts inside a WHEN. So:

- **Default**: one scenario = one `**WHEN**` = one `**THEN**` = one ID. Distinct input conditions that exercise different branches each get their own scenario, even when they share the same status/`message` THEN.
- **Do not** collapse distinct branches into one WHEN with `or` / `and/or` (e.g. unreachable **or** non-200 **or** malformed JWKS body). That lets a single test cite the ID while leaving other branches untested.
- **Split when** the WHENs are different failure/success modes, security-relevant edges, or code paths a reviewer would want independently covered (fetch failures, allowlist exact vs `/`-prefix, grace refresh vs no-refresh, missing vs mismatched header, …).
- **Roll up only when** the alternate setups are truly equivalent ways to reach the *same* behavior (e.g. two ways to omit the same required header) and you would not want a separate test per setup.
- Prefer a longer scenario list over an ungatable OR. More scenarios is expected and correct.

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

## Testability

Before finishing, walk every scenario:

- Ambiguous WHEN/THEN → rewrite now (no “should work” / “behaves correctly”).
- WHEN joined with `or` / `and/or` across distinct branches → split into separate scenarios now (see **One WHEN per scenario**).
- Not practical on the wire, but an export already exists → add the seam line on the requirement.
- Not practical on the wire and no export → leave the scenario; list its ID as `blocked — needs seam` (do not invent an export).
- Process-global env that isn’t the plugin’s primary path → prefer a seam if one exists; otherwise list as `deferred — process-global-env`.

Schema scenarios stay testable when the Configuration schema requirement lists fields, types, required/`one_of`/defaults completely enough to build configs without opening `schema.lua`.

## Summary output

After both files are written, the testability check is done, and validation passes, report:

- Paths of `spec.md` and `coverage.md`
- Requirement and scenario counts (and confirm every requirement/scenario has an `**ID**`)
- Seams added (scenario ID → export), plus any `deferred — process-global-env` or `blocked — needs seam` IDs (omit if none)
- Quirk-tagged scenarios (list them with IDs — these are the peer-review focal points)
- Any surfaces without a disposition (spec gaps — resolve in this run or during review)
