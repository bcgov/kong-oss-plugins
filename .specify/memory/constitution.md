<!--
Sync Impact Report
===================
Version change: 1.1.0 → 1.2.0
Rationale: Material expansion — adds two new principles (VIII, IX) that
establish verification as a first-class, required output of generation
rather than an optional extra. Closes the gap identified in
specs/001-jwks-endpoint/comparison-report.md (Issue 3) where Principles
II and IV classified un-requested tests as violations.
Modified sections:
  - Core Principles: added VIII "Verifiable by Default" covering both
    acceptance scenarios and Success Criteria; explicitly exempt from
    Principles II and IV.
  - Core Principles: added IX "Proportional Test Coverage"; MUST-level
    with enumerated triggers (branching, parsing/transformation,
    reusable helpers, error-handling paths).
Added sections:
  - Principle VIII (Verifiable by Default)
  - Principle IX (Proportional Test Coverage)
Removed sections: none
Templates requiring updates:
  - .specify/templates/plan-template.md ✅ updated (Constitution Check
    gates filled; Testing field mandates dual harness)
  - .specify/templates/spec-template.md ✅ no change needed (testing is
    a plan/tasks concern, not a spec concern)
  - .specify/templates/tasks-template.md ✅ updated (test tasks flipped
    from OPTIONAL to required-by-default; AS/SC traceability tags added)
  - .specify/templates/checklist-template.md ✅ updated (sample
    AS/SC → test-task traceability row added)
Follow-up TODOs: none
-->

# Kong OSS Plugins Constitution

## Core Principles

### I. Specification Supremacy

Written specifications (spec files under `specs/`) are the sole source
of truth for all generated code and configuration. No implementation
detail, behavior, or output is valid unless it traces directly to a
statement in the governing specification.

- Every code artifact MUST cite the specification requirement it
  fulfills (e.g., FR-001, acceptance scenario reference).
- If a specification does not exist for a feature, no code for that
  feature may be generated.
- Conflicts between specification and existing code MUST be resolved
  by updating one or the other explicitly, never by silent compromise.

### II. No Feature Expansion

Generated code MUST implement exactly what the specification states.
No inferred features, no "nice-to-have" additions, no undocumented
behaviors.

- Adding functionality beyond specification scope is prohibited.
- Defensive code for hypothetical scenarios not described in the spec
  MUST NOT be introduced.
- If the implementer identifies a useful addition, it MUST be proposed
  as a specification amendment first, never silently included.

### III. Deterministic Generation

AI-assisted generation MUST be deterministic and reproducible. The AI
makes no autonomous design decisions.

- Given the same specification input and project state, the same
  output MUST be produced.
- Design choices (naming, structure, patterns) MUST be dictated by the
  specification or by Kong plugin conventions (Principle VII), never
  by AI preference.
- The AI MUST NOT introduce stylistic variation, optimization, or
  refactoring unless the specification explicitly requests it.

### IV. Repeatability and Minimality

All generation processes MUST be repeatable with minimal, predictable
output and explicit termination criteria.

- Each generation step MUST have a defined entry condition, expected
  output, and exit condition.
- Output MUST be the minimum code required to satisfy the spec. No
  scaffolding, boilerplate, or structural overhead beyond what is
  functionally necessary.
- Termination criteria: generation is complete when every specification
  requirement has a corresponding implementation and no output exceeds
  specification scope.

### V. Explicit Ambiguity

Ambiguities and assumptions MUST be surfaced explicitly. Silent
resolution is prohibited.

- When a specification is ambiguous, generation MUST halt and flag the
  ambiguity with a `NEEDS CLARIFICATION` marker.
- Assumptions (e.g., default values, edge-case behaviors) MUST be
  documented in the spec's Assumptions section before code is written.
- No assumption may be embedded in code without a corresponding entry
  in the specification.

### VI. No Hidden State

IDE-dependent workflows, hidden state, and implicit agent iteration
are prohibited.

- All project state MUST be observable via the filesystem and git
  history. No state may reside in IDE sessions, agent memory, caches,
  or ephemeral context.
- Workflows MUST be reproducible from a clean checkout. If a process
  depends on prior agent context, that context MUST be persisted in
  spec files or plan artifacts.
- Implicit multi-pass iteration (where the agent autonomously refines
  output across hidden cycles) is forbidden. Each generation pass
  MUST be a discrete, user-visible step.

### VII. Kong Convention Adherence

All plugin code MUST be minimal, readable, and strictly adhere to
Kong plugin conventions.

- Plugin structure MUST follow the Kong plugin development kit (PDK)
  patterns: `handler.lua`, `schema.lua`, and rockspec at standard
  paths.
- Lua code MUST use the Kong PDK API (`kong.log`, `kong.request`,
  `kong.response`, etc.) rather than raw OpenResty/ngx APIs where a
  PDK equivalent exists.
- Code MUST be written for readability: short functions, descriptive
  names, no clever tricks. Complexity MUST be justified by a
  specification requirement.
- Dependencies MUST be minimized. External LuaRocks dependencies
  require explicit specification approval.

### VIII. Verifiable by Default

Verification is part of the feature, not an extra. Every externally
observable behavior and every measurable outcome in the specification
MUST have at least one automated check.

- Every **acceptance scenario** in `spec.md` (each Given/When/Then
  under a user story) MUST be covered by at least one automated
  integration test.
- Every **Success Criterion** (SC-###) in `spec.md` MUST be covered
  by at least one automated check. If a criterion is not mechanically
  verifiable (for example a subjective or purely business metric),
  `spec.md` MUST state the verification method explicitly in its
  Assumptions section; silent omission is not permitted.
- Verification tasks are explicitly exempt from Principle II ("No
  Feature Expansion") and from Principle IV's "minimum code required
  to satisfy the spec" clause. Generating tests for declared
  acceptance scenarios and Success Criteria is required output, not
  scope creep.
- Traceability is mandatory: every test task in `tasks.md` MUST cite
  the acceptance scenario ID and/or Success Criterion ID it verifies
  (for example `[US1-AS2]` or `[SC-003]`), and `tasks.md` MUST
  contain at least one test task for every such ID that appears in
  `spec.md`.

### IX. Proportional Test Coverage

Internal logic MUST be unit-tested when complexity, reuse, or failure
risk justifies isolation. This complements Principle VIII (which
covers externally observable behavior).

- A module, function, or helper MUST have unit tests if any of the
  following apply:
  - It contains non-trivial branching (two or more conditional paths
    that produce distinguishable outputs).
  - It performs parsing, encoding, decoding, or data transformation.
  - It is a reusable helper called from more than one caller.
  - It contains an error-handling path whose behavior is described by
    a specification requirement (for example an FR that mandates
    logging on failure and continuing).
- Trivial or framework-bound code MUST NOT be unit tested. This
  includes thin wrappers around PDK calls, pure delegation with no
  logic of its own, and declarative configuration. Such tests violate
  Principle IV's minimality clause without providing meaningful
  coverage.
- Unit tests generated under this principle are exempt from
  Principle II on the same basis as Principle VIII: they are required
  output when the triggers above apply.

## Generation Constraints

Rules governing how AI-assisted generation operates within this
project:

- **Input boundary**: The AI reads specifications, plan artifacts,
  existing source code, and Kong documentation. It does not access
  external services, APIs, or resources unless the specification
  instructs it.
- **Excluded source**: The AI MUST NOT read, reference, or derive
  patterns from `plugins/trust-registry/`. This directory is the
  active generation target and MUST be treated as output-only. All
  other plugin directories (e.g., `plugins/oidc/`,
  `plugins/jwt-keycloak/`, `plugins/trust-sign/`, etc.) SHOULD be
  used as reference for identifying Kong plugin structure and
  conventions.
- **Output boundary**: The AI produces Lua source files, rockspec
  files, test files, and documentation updates. It does not produce
  infrastructure configuration, deployment scripts, or CI pipelines
  unless explicitly specified.
- **Single-pass rule**: Each generation command (`/speckit.implement`,
  `/speckit.tasks`, etc.) produces one discrete output. The AI does
  not self-invoke subsequent commands or chain generation steps.
- **No interpolation**: The AI does not fill gaps in specifications
  with inferred content. Missing information results in `NEEDS
  CLARIFICATION` markers, not best-guess implementations.
- **Traceability**: Every generated file MUST be traceable to a task
  ID (from `tasks.md`) and a specification requirement.

## Development Workflow

The speckit pipeline enforces a sequential, auditable workflow:

1. **Specify** (`/speckit-specify`): Author the feature specification.
   No code exists yet. Output: `spec.md`.
2. **Clarify** (`/speckit-clarify`): Resolve all `NEEDS CLARIFICATION`
   markers. Output: updated `spec.md` with no unresolved markers.
3. **Plan** (`/speckit-plan`): Produce the implementation plan from
   the finalized spec. Output: `plan.md`, `research.md`,
   `data-model.md`, `contracts/`.
4. **Tasks** (`/speckit-tasks`): Decompose the plan into discrete,
   ordered tasks. Output: `tasks.md`.
5. **Implement** (`/speckit-implement`): Execute tasks sequentially.
   Each task produces exactly one deliverable. Output: source files.
6. **Checklist** (`/speckit-checklist`): Validate the implementation
   against the specification. Output: `checklist.md`.

**Gate rule**: No step may begin until its predecessor is complete and
its output has been reviewed. Skipping steps is prohibited.

**Commit rule**: Each completed step MUST be committed to version
control before the next step begins (enforced by git extension hooks).

## Governance

This constitution supersedes all informal practices, agent defaults,
and IDE behaviors. Compliance is mandatory for all code generation
within this repository.

- **Amendment procedure**: Amendments require a specification change
  (`/speckit-constitution` with explicit rationale), version increment,
  and review of all dependent templates.
- **Versioning**: This constitution follows semantic versioning.
  MAJOR for principle removals or incompatible redefinitions.
  MINOR for new principles or material expansions.
  PATCH for clarifications and wording fixes.
- **Compliance review**: Every pull request MUST include a
  constitution compliance check as part of its review checklist.
  Violations block merge.
- **Conflict resolution**: If a specification conflicts with this
  constitution, the constitution prevails. The specification MUST be
  amended to comply.

**Version**: 1.2.0 | **Ratified**: 2026-04-15 | **Last Amended**: 2026-04-21
