# Comparison Report: Spec-Kit vs OpenSpec

**Date**: 2026-05-19  
**Feature**: JWKS endpoint Kong plugin (same user story for both runs)  
**Spec-Kit plugin**: `plugins/trust-registry-ai/` — `specs/001-jwks-endpoint/`  
**OpenSpec plugin**: `plugins/trust-registry-ai-openspec/` — archived change `openspec/changes/archive/2026-05-19-trust-registry-ai-jwks/`, merged spec `openspec/specs/jwks-endpoint/spec.md`

## Executive summary

Both tools delivered a **working JWKS publisher** against the same story. OpenSpec used **fewer steps** and **lower cost** (**$2.00** vs **$3.98** per `/stats`); Spec-Kit produced **more planning artifacts** (constitution, research, quickstart, contracts, checklists).

On code quality for this run:

- **Spec-Kit** initially over-engineered PEM conversion (manual extraction), later corrected to OpenSSL JWK export in a follow-up commit. Final `trust-registry-ai` is solid.
- **OpenSpec** chose OpenSSL JWK export in `design.md` on the first pass — no manual-extraction detour — with logic split across `handler.lua` + `jwks.lua`.

Neither workflow generated automated tests without explicit prompting. Both relied on Docker + curl validation.

**Recommendation:** Prefer **OpenSpec** as the default SDD entry for new Kong work (lighter loop, archive/sync for spec drift). Keep Spec-Kit-style depth when you want constitution + research + quickstart in one toolchain, or stay on OpenSpec and add optional `/opsx:explore` / richer `design.md` for hard problems.

---

## Workflow comparison

| Aspect | Spec-Kit | OpenSpec (`core` profile) |
|--------|----------|-----------------------------|
| **Planning** | 4 commands: constitution, specify, plan, tasks | 1 command: `/opsx:propose` |
| **Implement** | `/speckit-implement` | `/opsx:apply` |
| **Cleanup** | Manual | `/opsx:archive` (+ spec sync) |
| **Wall-clock (this run)** | Not recorded | ~7m 7s (propose + apply + archive) |
| **Artifact volume** | High (`spec.md`, `plan.md`, `research.md`, `quickstart.md`, …) | Lean (`proposal`, `design`, `tasks`, delta `specs/`) |
| **Brownfield** | Full re-spec typical | Delta specs + archive merge |
| **Iteration** | Edit markdown between steps | Same; encouraged |

### Phase mapping

```text
Spec-Kit                          OpenSpec (core)
────────                          ───────────────
/speckit-constitution      ─┐
/speckit-specify           ─┼──►  /opsx:propose     (Opus 4.6)
/speckit-plan              ─┤
/speckit-tasks             ─┘
/speckit-implement       ──────►  /opsx:apply        (Sonnet 4.6)
(manual spec sync)       ──────►  /opsx:archive
```

---

## Cost and usage (Claude Code `/stats`, this repo)

Single OpenSpec session (propose → apply → archive). Spec-Kit figures from [spec-driven-development.md](../../docs/spec-driven-development.md).

| | Spec-Kit | OpenSpec |
|---|----------|----------|
| **Total cost** | **~$3.98** | **~$2.00** |
| **API duration** | Not recorded | **7m 7s** |
| **Opus 4.6** | 172 in / 104.3k out → **~$2.61** | 449 in / 8.7k out → **~$0.85** (propose) |
| **Sonnet 4.6** | 1.8k in / 88.2k out → **~$1.33** | 879 in / 12.2k out → **~$1.15** (apply + archive + in-apply checks) |
| **Haiku 4.5** | ~$0.04 | (negligible / not listed) |

OpenSpec also reported large **cache read** volumes (934.7k Opus, 2.2m Sonnet), which keep billed cost down versus raw output token counts.

**Workflow difference:** Spec-Kit used a separate Sonnet phase for interactive Docker validation (~28K footer tokens in that doc). OpenSpec folded Docker/curl checks into apply tasks 5.1–5.3 plus manual curl outside the session.

**Note:** The Claude Code session footer showed ~65,801 cumulative “tokens” at archive; `/stats` is the authoritative billing view (~21k output tokens, **$2.00** total). Do not compare footer meters directly to Spec-Kit `/stats` output columns.

Reference: [openspec-readme.md](../../docs/openspec-readme.md) (Costs section).

---

## Output comparison

| Output | Spec-Kit | OpenSpec |
|--------|----------|----------|
| Requirements spec | `specs/001-jwks-endpoint/spec.md` | Delta → `openspec/specs/jwks-endpoint/spec.md` |
| Design / research | `plan.md`, `research.md` | `design.md` |
| Tasks | `tasks.md` | `tasks.md` |
| Guardrails | `.specify/memory/constitution.md` | `openspec/config.yaml` `context` |
| Extras | quickstart, data-model, contracts, checklists | None (unless expanded workflow) |
| Plugin directory | `plugins/trust-registry-ai/` | `plugins/trust-registry-ai-openspec/` |

---

## Code outcome (three-way)

Validated OpenSpec plugin 2026-05-19 with `docker compose -f docker-compose.validate.yml` + curl (see [comparison-report-openspec.md](./comparison-report-openspec.md)).

| Dimension | Human `trust-registry` | Spec-Kit `trust-registry-ai` | OpenSpec `trust-registry-ai-openspec` |
|-----------|------------------------|------------------------------|---------------------------------------|
| PEM→JWK | OpenSSL JWK export | OpenSSL JWK export (after follow-up) | OpenSSL JWK export (first pass) |
| URI / keyset | `get_uri_captures()` + config | `get_path():match` | `ngx.re.match` on path |
| Keyset query | `each_for_set` | `each_for_set` | `each()` + filter in Lua |
| Unknown keyset | 404 | 404 | 404 |
| Config fields | Optional `key_set` | Zero | Zero |
| `use: sig` on PEM keys | Yes | Yes | No (in curl output) |
| Module layout | handler + pem helper | handler + pem_to_jwk | handler + jwks |
| Local validation | (baseline) | Passed (per Spec-Kit doc) | **Passed** (curl) |

**Rabbit hole avoided (OpenSpec):** Manual PEM parameter extraction (Spec-Kit’s original mistake, documented in [comparison-report.md](./comparison-report.md)).

**Rabbit holes / drift (OpenSpec):** tasks.md cited wrong PDK helpers. Unknown-keyset behavior was 404 in code; merged `openspec/specs/jwks-endpoint/spec.md` matches (archive corrected an earlier 200-empty draft).

---

## Ticket criteria: OpenSpec benefits

| Claim | Result |
|-------|--------|
| Lighter 3-phase workflow | **Yes** — propose / apply / archive vs 5–7 Spec-Kit steps |
| Less upfront overhead | **Yes** — ~$0.85 Opus propose vs ~$2.61 Spec-Kit planning; fewer files |
| Iterative proposals | **Yes** — artifacts editable between phases |
| Spec drift / archive | **Yes** — merged `openspec/specs/jwks-endpoint/spec.md`, archive folder retained |
| Brownfield / delta specs | **Supported** — not exercised on this greenfield plugin |
| Same models as Spec-Kit | **Yes** — Opus 4.6 propose, Sonnet 4.6 apply |

---

## Recommendations / next steps

1. **Default to OpenSpec** for new plugins; put repo conventions in `openspec/config.yaml` `context`.
2. **Keep comparison plugins separate** — `trust-registry-ai` (Spec-Kit) vs `trust-registry-ai-openspec` (OpenSpec); do not overwrite when re-running either tool.
3. **Before archive**, consider `/opsx:verify` to catch delta-spec vs implementation mismatches (e.g. unknown keyset status code).
4. **Tests:** Add explicit test tasks in propose prompt or config rules if busted coverage is required (both tools skipped tests here).
5. **Optional:** Run Spec-Kit validation token phase vs OpenSpec “validation in apply” when comparing total cost of “done and verified.”

---

## Related

- [OpenSpec README](../../docs/openspec-readme.md)
- [Spec-Kit README](../../docs/spec-driven-development.md)
- [Human vs Spec-Kit AI](./comparison-report.md)
- [Human vs OpenSpec AI](./comparison-report-openspec.md)
