# Creating plugins using spec-driven development (OpenSpec and Claude Code)

This document captures the process of creating a new Kong plugin using spec-driven development (SDD) with [OpenSpec](https://github.com/Fission-AI/OpenSpec) and Claude Code. Along with step-by-step usage instructions, some broader commentary on the process from a user standpoint is included.

The OpenSpec AI plugin is in `plugins/trust-registry-ai-openspec`. The Spec-Kit AI plugin (`plugins/trust-registry-ai`) and human plugin (`plugins/trust-registry`) are left unchanged for comparison. OpenSpec artifacts live under `openspec/` (archived change in `openspec/changes/archive/2026-05-19-trust-registry-ai-jwks/`, merged spec in `openspec/specs/jwks-endpoint/`).

- [Human vs Spec-Kit AI](../specs/001-jwks-endpoint/comparison-report.md)
- [Human vs OpenSpec AI](../specs/001-jwks-endpoint/comparison-report-openspec.md)
- [Spec-Kit vs OpenSpec workflow](../specs/001-jwks-endpoint/speckit-vs-openspec.md)

## Why OpenSpec?

OpenSpec addresses several concerns identified during the Spec-Kit experience:

- **Lighter workflow** — 3 core phases by default (propose → apply → archive), with optional deeper phases (`explore`, `sync`, `verify`, or expanded `new` / `continue` / `ff`)
- **Better for brownfield** — supports *delta specs* that describe only what changes, rather than requiring a full feature specification
- **More iterative** — proposals and design can be updated as new information surfaces
- **Spec drift mitigation** — `/opsx:archive` merges delta specs into `openspec/specs/` and moves the change to an archive folder

## Branch and clean-room setup

Use branch `001-jwks-endpoint-openspec` for OpenSpec work. **Do not modify** Spec-Kit outputs:

- `plugins/trust-registry-ai/` — Spec-Kit plugin (frozen)
- `specs/001-jwks-endpoint/` — Spec-Kit specs/plan/tasks (frozen)

OpenSpec implementation goes in **`plugins/trust-registry-ai-openspec/`**. Wall off `trust-registry`, `trust-registry-ai`, and `specs/001-jwks-endpoint` during generation.

After the OpenSpec run, merge into `001-jwks-endpoint` for side-by-side comparison (both AI plugins present).

## Setup

### 1. Install OpenSpec

Requires **Node.js ≥ 20.19.0**.

Global install:

```sh
npm install -g @fission-ai/openspec@latest
```

Or install locally in the repo (used in this project):

```sh
npm install @fission-ai/openspec@latest --prefix .tools
export PATH="$PWD/.tools/node_modules/.bin:$PATH"
```

Verify:

```sh
openspec --version
```

### 2. Install Claude Code (or other agent of your choice)

```sh
curl -fsSL https://claude.ai/install.sh | bash
```

If using an API key, set the `ANTHROPIC_API_KEY` environment variable:

```sh
export ANTHROPIC_API_KEY="your-api-key-here"
```

Verify (may need to restart WSL with `wsl --shutdown`, or restart your machine):

```bash
claude
```

Set theme and choose *Yes* to use the API key.

### 3. Initialize in an existing project

From the repo root:

```sh
openspec init . --tools claude --force
```

This creates:

- `openspec/specs/`, `openspec/changes/`, `openspec/config.yaml`
- `.claude/skills/openspec-*` and `.claude/commands/opsx/`

Restart the terminal (or Claude Code) after init so slash commands are available.

Add Kong plugin context to `openspec/config.yaml` (optional but recommended):

```yaml
schema: spec-driven

context: |
  Kong OSS plugin repository. Lua (LuaJIT), Kong PDK only.
  Plugin layout: plugins/<name>/src/{handler,schema}.lua + rockspec.
  Follow patterns from existing plugins; do not read plugins/trust-registry or plugins/trust-registry-ai.
  Output plugin: plugins/trust-registry-ai-openspec/
```

### 4. Wall off the existing target plugin from the agent

Create or edit `.claude/settings.local.json`:

```json
{
  "permissions": {
    "deny": [
      "Read(plugins/trust-registry/**)",
      "Read(plugins/trust-registry-ai/**)",
      "Read(specs/001-jwks-endpoint/**)"
    ]
  }
}
```

> **Note:** Search can still surface file names. For strict clean-room runs, consider denying search/glob on those paths or removing the directories from the branch before starting.

### 5. Open Claude Code

`--verbose` shows token usage. Use **Opus 4.6** for planning; **Sonnet 4.6** for implementation (same models as the [Spec-Kit run](./spec-driven-development.md)).

```sh
claude --verbose --model claude-opus-4-6
```

---

## Using OpenSpec and Claude Code

OpenSpec’s default **`core` profile** maps to three practical phases. Optional commands are listed at the end.

| Phase | Spec-Kit analogue | OpenSpec command | Model |
|-------|-------------------|------------------|-------|
| 1 — Plan | constitution + specify + plan + tasks | `/opsx:propose` | Opus |
| 2 — Implement | implement | `/opsx:apply` | Sonnet |
| 3 — Archive | (manual spec sync) | `/opsx:archive` | Either |

### Phase 1 — Propose (planning artifacts)

Creates `openspec/changes/<name>/` with `proposal.md`, delta `specs/`, `design.md`, and `tasks.md` in one step.

In Claude Code:

```text
/opsx:propose trust-registry-ai-jwks
```

If Claude shows a multiple-choice menu about “AI trust registry” scope, choose **Type something** and paste the block below. The change name `trust-registry-ai-jwks` is only a folder label; the feature is the same JWKS publisher as the [Spec-Kit run](./spec-driven-development.md).

Paste this text **verbatim** for a fair comparison (matches `/speckit-specify` + `/speckit-plan`, with only the plugin name changed for a separate output directory):

```text
Story: As an SDX Edge Server host, I want to be able to publish my Edge Server public keys, so that other Edge Servers can use it to validate any JSON Web Signature (JWS) documents that my server creates.

Technical background: The SDX Edge Server host will be able to use a gateway pattern to register public keys.  To make these keys available to others, there has to be an endpoint that takes the Kong `keys` and `keysets` and returns a document in JWK Set (JWKS) (RFC-7517) format.  The endpoint should be able to return all keys or provide a keyset path parameter and return only the keys for that particular keyset.  Kong's keys entity allows for storing a pem formatted public key or a jwk.  A JWKS always returns jwk objects so it will need to convert the pem to a jwk while building the response document.

A decision was made to use a Kong plugin to perform this logic, where the route will be:
paths:
  - '/.well-known/jwks.json'
  - '~/keysets/(?<key_set>.+)/.well-known/jwks.json'
method:
  - GET

The Kong plugin does not need any configuration parameters.  It will use the optional key_set path parameter to filter the results.

Name the plugin `trust-registry-ai-openspec`. No explicit technical constraints beyond those in the written specification. All implementation details must strictly adhere to Kong plugin guidelines and the stated spec; avoid undocumented behaviors, dependencies, or design assumptions.
```

**Comparison note:** Do not add extra hints (e.g. “survey lua-resty-openssl”) that Spec-Kit did not receive. Document any process differences in [speckit-vs-openspec.md](../specs/001-jwks-endpoint/speckit-vs-openspec.md) instead.

If a change folder already exists from an earlier attempt, remove it before re-running propose:

```sh
rm -rf openspec/changes/trust-registry-ai-jwks
rm -rf plugins/trust-registry-ai-openspec   # only if you want a fresh apply
```

**Artifacts produced:**

```text
openspec/changes/trust-registry-ai-jwks/
├── proposal.md
├── design.md
├── tasks.md
├── specs/jwks-endpoint/spec.md   # delta spec (ADDED/MODIFIED/REMOVED)
└── .openspec.yaml
```

CLI equivalents (if not using slash commands):

```sh
openspec new change "trust-registry-ai-jwks"
openspec status --change trust-registry-ai-jwks
openspec instructions proposal --change trust-registry-ai-jwks --json
# ... create each artifact per instructions, then re-check status
```

**Phase 1 (this run):** `/opsx:propose` on **Opus 4.6** (~3m 13s). Billed usage is in the [Costs](#costs) table (Opus row). Spec-Kit planning was ~**$2.61** Opus alone for constitution + specify + plan + tasks ([spec-driven-development.md](./spec-driven-development.md)).

---

### Phase 2 — Apply (implementation)

Switch to Sonnet 4.6 to reduce cost:

```text
/model
```

Select `Sonnet`. Switching models clears conversation history; decisions should live in the change artifacts.

In Claude Code:

```text
/opsx:apply trust-registry-ai-jwks
```

The agent reads `proposal.md`, `design.md`, `specs/`, and `tasks.md`, implements the plugin, and checks off tasks in `tasks.md`.

**Output:** `plugins/trust-registry-ai-openspec/` (and any validation assets referenced in tasks).

**Phase 2 (this run):** `/opsx:apply` on **Sonnet 4.6** (~2m 40s), including in-session Docker checks (tasks 5.1–5.3). Most of the Sonnet row in [Costs](#costs) is apply + archive. Spec-Kit `/speckit-implement` was ~**$1.33** Sonnet ([spec-driven-development.md](./spec-driven-development.md)).

---

### Phase 3 — Archive (cleanup and spec merge)

```text
/opsx:archive trust-registry-ai-jwks
```

**What archive does:**

1. Checks artifacts and task completion (warns if tasks remain open)
2. Offers to **sync** delta specs into `openspec/specs/<capability>/spec.md` if not already synced
3. Moves the change folder to `openspec/changes/archive/YYYY-MM-DD-trust-registry-ai-jwks/`

CLI equivalent:

```sh
openspec archive trust-registry-ai-jwks
```

After archive, `openspec/specs/jwks-endpoint/spec.md` is the merged source of truth for the capability.

**Phase 3 (this run):** `/opsx:archive` (~1m 14s), same Claude Code session — included in Sonnet [Costs](#costs).

**Session total (`/stats`):** **$2.00**, **7m 7s** API time (propose + apply + archive). The Claude Code footer showed ~65,801 cumulative “tokens” for the session; that meter includes cache-heavy context and does not match input+output alone — use `/stats` for billing (see [Costs](#costs)).

---

### Validate

After implementation, validate locally:

```sh
docker compose -f docker-compose.validate.yml up -d --build
```

```bash
(echo "=== CHECK 1: GET /.well-known/jwks.json ===" \
  && STATUS=$(curl -s -o /tmp/jwks-all.json -w "%{http_code}" \
    http://localhost:8000/.well-known/jwks.json) \
  && echo "HTTP $STATUS" \
  && cat /tmp/jwks-all.json | python3 -m json.tool 2>/dev/null \
  || cat /tmp/jwks-all.json)

(echo "=== CHECK 2: GET keyset JWKS ===" \
  && STATUS=$(curl -s -o /tmp/jwks-set.json -w "%{http_code}" \
    http://localhost:8000/keysets/signing/.well-known/jwks.json) \
  && echo "HTTP $STATUS" \
  && cat /tmp/jwks-set.json | python3 -m json.tool 2>/dev/null \
  || cat /tmp/jwks-set.json)
```

`local/kong-validate/kong.yaml` defines test keys, keysets, routes, and the plugin attachment.

---

### Optional additional phases

| Command | When to use |
|---------|-------------|
| `/opsx:explore` | Requirements unclear; compare approaches before proposing |
| `/opsx:sync` | Merge delta specs into `openspec/specs/` before archive (archive can prompt) |
| `/opsx:verify` | Check implementation vs artifacts before archive |
| `/opsx:new` + `/opsx:continue` or `/opsx:ff` | Expanded workflow: step-by-step or fast-forward artifact creation instead of `/opsx:propose` |

Enable expanded workflows:

```sh
openspec config profile   # select workflows
openspec update
```

---

### Follow-up updates and delta specs

For bounded changes to an existing capability, add a new change with delta specs (`## ADDED Requirements`, `## MODIFIED Requirements`, etc.) instead of re-running the full propose flow.

Simple guidance for when to update specs:

- If a user of the plugin would notice the change → update the spec (via a new change + archive)
- If only a developer reading the code would notice → direct edit may suffice

---

## Commentary

### Approvals

File changes and terminal commands require approval in Claude Code. Loosen guardrails once comfortable with the workflow.

### Human intervention

Edit any artifact (`proposal.md`, `design.md`, `tasks.md`, delta specs) between phases. OpenSpec expects iteration.

### Did the model cheat?

Wall-off rules live in [`.claude/settings.local.json`](../.claude/settings.local.json) (not committed):

```json
"deny": [
  "Read(plugins/trust-registry/**)",
  "Read(plugins/trust-registry-ai/**)",
  "Read(specs/001-jwks-endpoint/**)"
]
```

Run Claude Code with project root `~/kong-oss-plugins` so this file applies.

**Verified after the OpenSpec run (2026-05-19):** Explicit `Read` requests for files under those three globs were **inaccessible** (denied as expected). Reads outside the globs (e.g. `plugins/trust-registry-ai-openspec/`) still worked. The deny rules are working for **`Read`**, not for every shell command.

**During the run:** Watch the transcript for **search** or **`ls`** under `plugins/` — those can still reveal that `trust-registry` / `trust-registry-ai` exist without reading their contents (same limitation as the [Spec-Kit run](./spec-driven-development.md)).

### Costs

End-of-session usage from `/stats` in Claude Code (one session: propose → apply → archive):

| Model        | Input | Output | Cache read | Cache write | Cost    |
|--------------|-------|--------|------------|-------------|---------|
| Opus 4.6     | 449   | 8.7k   | 934.7k     | 26.3k       | **$0.85** |
| Sonnet 4.6   | 879   | 12.2k  | 2.2m       | 78.6k       | **$1.15** |
| **Total**    |       | **~20.9k** |            |             | **$2.00** |

- **API duration:** 7m 7s (matches phased work). Wall clock was longer (~56m) due to approvals and breaks.
- **Phase mapping:** Opus row ≈ `/opsx:propose`; Sonnet row ≈ `/opsx:apply` + `/opsx:archive` + in-apply validation.
- **Footer meter:** The UI reported ~65,801 session “tokens” at archive time; that count is not the same as input+output and is not used above.

Rates: [Anthropic pricing](https://platform.claude.com/docs/en/about-claude/pricing). Reference: Spec-Kit run **~$3.98** total ([spec-driven-development.md](./spec-driven-development.md)) — OpenSpec **~50% lower** for this feature, with validation largely inside apply rather than a separate ~28K-token validation chat.

**Archived to:** `openspec/changes/archive/2026-05-19-trust-registry-ai-jwks/` · **Merged spec:** `openspec/specs/jwks-endpoint/spec.md`

### Using other agents

This run used **Claude Code** only. OpenSpec also supports Cursor, Codex, Windsurf, Gemini, GitHub Copilot, and others — see [OpenSpec integrations](https://github.com/Fission-AI/OpenSpec/blob/main/docs/cli.md) and `openspec init --tools <list>`.

---

## Related

- [Spec-Kit README](./spec-driven-development.md) — prior approach
- [Comparison report: human vs Spec-Kit AI](../specs/001-jwks-endpoint/comparison-report.md)
- [Comparison report: human vs OpenSpec AI](../specs/001-jwks-endpoint/comparison-report-openspec.md)
- [Comparison report: Spec-Kit vs OpenSpec](../specs/001-jwks-endpoint/speckit-vs-openspec.md)
