<!--
Sync Impact Report
===================
Version change: 1.0.0 → 1.1.0
Modified sections:
  - Generation Constraints: added Excluded Source rule
    (plugins/trust-registry/ is output-only, never read as reference)
Added sections: none
Removed sections: none
Templates requiring updates:
  - .specify/templates/plan-template.md ✅ no change needed
  - .specify/templates/spec-template.md ✅ no change needed
  - .specify/templates/tasks-template.md ✅ no change needed
  - .specify/templates/checklist-template.md ✅ no change needed
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

**Version**: 1.1.0 | **Ratified**: 2026-04-15 | **Last Amended**: 2026-04-15
