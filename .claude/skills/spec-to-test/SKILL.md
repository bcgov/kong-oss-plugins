---
name: spec-to-test
description: Generate clean-room automated tests (Playwright integration + busted unit/schema) for a Kong plugin from its OpenSpec spec. Use when the user asks to generate tests for a plugin from its spec, run spec-to-test, or implement spec-driven plugin tests.
---

Generate automated tests for a Kong plugin from `openspec/specs/<plugin>/spec.md`, **clean-room**: the spec (plus this skill) is the only description of plugin behavior you may use. Tests assert what the spec says — never what the implementation happens to do. Spec gaps must surface as test failures or reported blockers, not get silently patched over.

**Input**: a plugin name (e.g. `trust-sign`).

**Outputs**:

1. Busted specs under `plugins/<plugin>/spec/` (+ `.busted` and `spec/resty-runner.lua` if missing)
2. Playwright specs under `testsuite/tests/plugins/<plugin>/`
3. A plugin helper `testsuite/helpers/<plugin>.ts`
4. When applicable: an interop spec under `testsuite/tests/interop/` and shared key fixtures under `testsuite/local/kong/fixtures/keys/`
5. A **generation summary** (format at the end) in your final report — the user pastes it into the PR

## Clean-room rules

**Allowed context** (exhaustive):

1. This skill
2. `openspec/specs/<plugin>/spec.md` — the only behavioral input. When writing interop tests, also the **Interop / shared contract** section of the peer plugin's `spec.md`
3. Shared, plugin-neutral helpers: `testsuite/helpers/kong.ts`, `testsuite/helpers/upstream.ts`, `testsuite/helpers/logger.ts`, `testsuite/helpers/deep-merge.ts`
4. Helpers and fixtures you create in this run
5. Harness infrastructure files: `testsuite/playwright.config.ts`, `testsuite/package.json`, `testsuite/docker-compose*.yml`, any plugin's `.busted` / `spec/resty-runner.lua`

**Forbidden context** — do not open, even "just to check":

- Plugin source under `plugins/*/src/` (any plugin). Busted tests may `require` modules of the plugin under test at **runtime**; you may not read them.
- `openspec/specs/*/coverage.md` — spec-review aid only
- Existing test bodies: anything under `testsuite/tests/plugins/**` or `plugins/*/spec/*_spec.lua`. They predate these standards and are not exemplars. The canonical example below is your only exemplar.
- Plugin-behavior-specific helpers: `testsuite/helpers/keycloak.ts`, `e2e-test.ts`, `prepare-client-and-service.ts`, `api.ts`

**Preflight**

1. **Enable clean-room** (agent runs this — do not skip):

   ```sh
   .claude/skills/spec-to-test/clean-room-on.sh
   ```

   Host-agnostic: creates `.claude/clean-room.active` and syncs deny patterns from `clean-room-patterns.txt` into:

   - **Cursor** — managed block in repo-root `.cursorignore`
   - **Claude Code** — activates the always-registered `PreToolUse` guard (`.claude/settings.json` → `clean-room-guard.sh`), which no-ops when the flag is absent

   Does **not** block test output paths (you must still write/delete there). Scripts live next to this skill. The user may run `clean-room-on.sh` themselves before opening a **fresh** agent chat for strongest isolation (mid-session enable cannot erase already-loaded context).

2. Do **not** open forbidden paths this turn (Read, Grep, or `cat`/`rg` via Shell). Recently viewed / open tabs are not an automatic hard-stop — if forbidden **contents** are clearly already in this chat (attached or earlier reads of plugin source / coverage / legacy tests), tell the user to start a fresh chat with clean-room already on, then stop. Do not refuse merely because those files appear in an IDE recent list.

3. Stop and tell the user when `openspec/specs/<plugin>/spec.md` does not exist, or any Requirement/Scenario lacks an `**ID**` line → the spec must be generated/backfilled with `reverse-spec` first.

Never modify `plugins/<plugin>/src/**` or the spec. If the spec looks wrong or untestable, report it — do not fix it.

## Procedure

1. **Clean-room on** (see Preflight) if not already enabled this run.
2. **Read the spec.** Build a scenario inventory: every scenario ID, its tag (none / `quirk` / `pending — <ticket>`), its harness placement (rules below), and its disposition. Every ID ends up either placed, or listed as `blocked — needs seam` / `deferred — process-global-env`. Out-of-scope bullets get **zero** tests; surfaces without a requirement get zero tests (gaps belong in spec review, not here).
3. **Delete legacy tests** for this plugin by path, without reading them: `plugins/<plugin>/spec/*_spec.lua` and `testsuite/tests/plugins/<plugin>/**`. Keep/create runner infrastructure (`.busted`, `spec/resty-runner.lua`). Do not leave a mixed old+new suite. List deletions in the summary.
4. **Create shared key files** if a scenario needs signing keys and `testsuite/local/kong/fixtures/keys/` lacks them (see Fixtures). Do not change compose/nginx — `/__fixtures__/` is already wired.
5. **Write the plugin helper** `testsuite/helpers/<plugin>.ts` (contract below) — from this skill and the spec's Configuration schema requirement, not copied from other plugins' helpers.
6. **Write busted tests**, then **Playwright tests**, then the **interop spec** when applicable.
7. **Run both suites** (commands below) and triage per the failure policy.
8. **Clean-room off** (always, even if generation stopped early):

   ```sh
   .claude/skills/spec-to-test/clean-room-off.sh
   ```

9. **Report** the generation summary.

## Harness placement

- **Playwright** (`testsuite/tests/plugins/<plugin>/*.spec.ts`) — the default home for anything externally observable: request/response headers, status codes, token/claim contents on the wire, digests, config-driven gating, interop flows.
- **Busted** (`plugins/<plugin>/spec/*_spec.lua`) — config schema validation, and scenarios whose requirement carries a **seam line** (`Unit tests MAY call <export> (require "<module>")`). Only `require` the module `schema` (for schema tests) and modules named in seam lines — never invent module paths.
- **Not wire-observable and no seam line** → do not read source to find a call site, do not invent a second Kong stack, do not skip or soft-assert. List the ID as `blocked — needs seam` in the summary and move on. Unblocking (exporting a helper + adding the seam line to the spec) is a human/refactor step.
- **Process-global env vars** (e.g. a key-path override read by the whole Kong process): the shared compose stack runs with such vars **unset** — never add a second Kong instance or Playwright project for them. Prefer busted via a seam (reload or mock `os.getenv` between cases if the value is captured at load). If no seam exists, list the ID as `deferred — process-global-env`.

Do not unit-test thin PDK wrappers, pure delegation, or the full handler with a mocked Kong PDK — that behavior belongs in Playwright. Do not Playwright-round-trip a pure helper the spec seams for busted.

## Scenario IDs and citations

Requirement IDs are structural (grouping + seam attachment). Do not cite them in `[Verifies:]`. Completion is scenario IDs only.

Every test cites the scenario it verifies, immediately above the test:

```ts
// [Verifies: trust-sign.direction-gating.unset-noop]
test("direction unset is a no-op", async ({ request }) => { … });
```

```lua
-- [Verifies: trust-sign.configuration-schema.required-fields]
it("rejects config missing keyid", function() … end)
```

Prefer one test per scenario. A test may cite multiple IDs only when it genuinely asserts every cited scenario's THEN outcomes.

**Completion gate**: every scenario ID in `spec.md` appears in at least one `[Verifies: …]` tag across busted + Playwright (+ interop files), except IDs reported as `blocked — needs seam` or `deferred — process-global-env`. A citation alone is not completion — the test must assert the scenario's **specific** THEN outcomes (see anti-patterns).

## Tags → test disposition

| Spec tag | Test behavior |
|---|---|
| *(none)* — contract | Hard assert |
| `quirk` | Hard assert, identically to contract (the tag is spec-review metadata; you may echo the reason in a comment) |
| `pending — <ticket>` | Assert the **desired** behavior; mark expected-failure; cite the ticket |

**Playwright pending** — use `test.fail` so the test runs and must fail until the bug is fixed (an unexpected pass then fails CI, prompting removal of the annotation and the spec tag together):

```ts
// [Verifies: trust-sign.some.scenario]
// pending — APS-XXXX
test("…", async ({ request }) => {
  test.fail(true, "pending — APS-XXXX");
  // assertions for *desired* behavior
});
```

Never use `test.fixme` / `test.skip` / busted `pending()` for a `pending` tag — those skip execution and will not detect accidental fixes.

**Busted pending** — prefer moving the scenario to Playwright if it is observable over HTTP. If it must stay in busted, use the shared helper at `plugins/_testlib/xfail.lua`. It treats only luassert assertion failures as the expected failure and re-raises module-load / runtime errors. Point the plugin's `.busted` `lpath` at `_testlib` (setting `lpath` replaces busted's defaults, so the `./src` patterns must be restated):

```
lpath = "./src/?.lua;./src/?/?.lua;./src/?/init.lua;../_testlib/?.lua"
```

```lua
local xfail = require "xfail"

-- [Verifies: …]
-- pending — APS-XXXX
it("desired behavior (xfail APS-XXXX)", function()
  xfail("APS-XXXX", function()
    -- assertions for *desired* behavior; must currently fail
  end)
end)
```

## Test environment

The compose stack (`testsuite/docker-compose.yml`, project `e2e`) runs Kong in CP/DP mode with plugins **baked into the `kong:e2e` image** at build time:

- **Admin API**: default `http://kong.localtest.me:8001` (control plane). Import `KONG_ADMIN_URL` from `testsuite/helpers/kong.ts`.
- **Proxy**: default `http://kong.localtest.me:8000` — nginx load balancer round-robining **3 Kong data-plane replicas**. Import `KONG_PROXY_URL` from the same module. Routes must set `hosts: ["kong.localtest.me"]`.
- **Upstream echo**: [httpbun](https://github.com/sharat87/httpbun) at `upstream.localtest.me:80` inside the network. Point services at it via `upstreamServiceDefaults` from `testsuite/helpers/upstream.ts`. Useful endpoints: `/headers` (echoes request headers as JSON), `/anything` (echoes method/headers/body), `/status/{code}`, `/response-headers?Header=value` (pre-set response headers), `/bytes/{n}` (arbitrary body; `/bytes/0` or `/status/204` for empty), `/mix/…/b64=…`. Do not introduce a per-plugin upstream unless echo cannot express the behavior.
- **CP→DP propagation**: entities created via the Admin API are not instantly routable, and each of the 3 DP replicas syncs independently. Never sleep blindly; call `waitForRouteReady` from `helpers/kong.ts` after provisioning.
- **Static fixtures URL**: the nginx LB already serves `testsuite/local/kong/fixtures/` at `http://kong:8000/__fixtures__/…` (host/Playwright: `${KONG_PROXY_URL}/__fixtures__/…`). Do not add Kong routes or edit compose/nginx for fixtures.

URLs come from env (`KONG_ADMIN_URL`, `KONG_PROXY_URL`) with the defaults above — compose sets both for the Playwright container; host runs use the same defaults (`localtest.me` resolves to `127.0.0.1`). Do **not** hardcode host:port in plugin helpers or re-export URL constants from `helpers/<plugin>.ts`. Do not rely on Playwright `baseURL` alone (the suite needs both Admin and Proxy).

## Playwright standards

Layout: `testsuite/tests/plugins/<plugin>/*.spec.ts`. Prefer focused files grouped by requirement (`direction.spec.ts`, `request-digest.spec.ts`, …); a single `default.spec.ts` is fine for small plugins. Interop: `testsuite/tests/interop/<producer>-<consumer>.spec.ts`.

Lifecycle (required):

- Unique run-ID prefix on every entity name (`<plugin>-<Date.now()>`)
- Stale-entity pre-cleanup for the plugin's name prefix in `beforeAll`
- Provision + readiness probe before asserting
- Cleanup in `afterAll` (and `afterEach` where a test provisions its own entities)

### Plugin helper contract — `testsuite/helpers/<plugin>.ts`

Import `KONG_ADMIN_URL`, `KONG_PROXY_URL`, `provisionKong`, and `waitForRouteReady` from `testsuite/helpers/kong.ts` (do not redefine or hardcode those URLs; do not reimplement the readiness probe).

Export:

- `provisionPluginRoute(request, { prefix, config, serviceTags?, … })`:
  1. POST a service (name `<prefix>-svc-<n>`, spread `upstreamServiceDefaults`, `tags: serviceTags` when given), a route (name `<prefix>-rt-<n>`, `hosts: ["kong.localtest.me"]`, `paths: ["/<prefix>-<n>"]`, `strip_path: true`), and the plugin (`{ name: "<plugin>", route: { id }, config }`) via `provisionKong`. Valid `config` values come from the spec's Configuration schema requirement; key paths come from Fixtures below.
  2. Call `await waitForRouteReady(request, routePath)` (shared helper: polls `/headers` until non-404, then **5 consecutive** non-404s across the round-robined DPs).
  3. Return `{ routePath, serviceId, routeId, pluginId }`.
- `cleanupByPrefix(request, prefix)`: list `GET ${KONG_ADMIN_URL}/routes?size=1000` and `/services?size=1000` (follow `next` pages), delete routes whose name starts with the prefix (route-scoped plugins cascade), then matching services.

Add extra helpers as the plugin's scenarios demand (e.g. decoding a JWT from an echoed header) — in this file, not in shared helpers. Do not change the behavior of existing shared helper exports.

### Canonical example

The only exemplar you may pattern-match against (config values here are illustrative — take real fields from the spec):

```ts
import { test, expect } from "@playwright/test";
import { KONG_PROXY_URL } from "../../../helpers/kong";
import {
  provisionPluginRoute,
  cleanupByPrefix,
} from "../../../helpers/trust-sign";

const PREFIX = `trust-sign-${Date.now()}`;

test.describe("trust-sign — direction gating", () => {
  test.beforeAll(async ({ request }) => {
    await cleanupByPrefix(request, "trust-sign-"); // stale entities from prior runs
  });

  test.afterAll(async ({ request }) => {
    await cleanupByPrefix(request, PREFIX);
  });

  // [Verifies: trust-sign.direction-gating.unset-noop]
  test("direction unset is a no-op", async ({ request }) => {
    const { routePath } = await provisionPluginRoute(request, {
      prefix: PREFIX,
      config: {
        keyid: "rsa-2048",
        private_key_location: "/tmp/kong/fixtures/keys/rsa-2048.pem",
        // direction deliberately unset
      },
    });

    const res = await request.get(`${KONG_PROXY_URL}${routePath}/headers`);
    expect(res.status()).toBe(200);
    const echoedHeaders = (await res.json()).headers; // upstream request headers, echoed by httpbun
    expect(echoedHeaders["X-Edge-Token"]).toBeUndefined();
    expect(echoedHeaders["Content-Digest"]).toBeUndefined();
    expect(res.headers()["x-edge-token"]).toBeUndefined(); // response side untouched too
  });
});
```

## Busted standards

Layout: `plugins/<plugin>/spec/*_spec.lua`, run from the plugin directory. Busted's default `lpath` supplies `./src/?.lua`, so `require "schema"` (etc.) resolves against the plugin's own source at runtime.

If the plugin lacks them, create `plugins/<plugin>/.busted`:

```lua
return {
  default = {
    lua = "spec/resty-runner.lua",
    verbose = true,
    coverage = false,
    output = "gtest",
  },
}
```

and `plugins/<plugin>/spec/resty-runner.lua` (verbatim — this is the repo-wide runner):

```lua
#!/usr/bin/env resty


local RESTY_FLAGS = os.getenv("BUSTED_RESTY_FLAGS") or "-c 4096 -e 'setmetatable(_G, nil)'"

-- rebuild the invoked commandline, while inserting extra resty-flags
local cmd = {
  "exec",
  arg[-1],
  RESTY_FLAGS
}
for i, param in ipairs(arg) do
  table.insert(cmd, "'" .. param .. "'")
end

local _,
  _,
  rc = os.execute(table.concat(cmd, " "))
os.exit(rc)
```

### Schema validation

Config-schema scenarios are busted tests against Kong's own validator (do not test them via Admin API round-trips):

```lua
local Schema = require "kong.db.schema"
local schema_def = require "schema"

local config_def
for _, field in ipairs(schema_def.fields) do
  if field.config then
    config_def = field.config
    break
  end
end
local config_schema = assert(Schema.new(assert(config_def, "schema missing config field")))

-- [Verifies: <plugin>.configuration-schema.required-fields]
it("rejects config missing keyid", function()
  local ok, err = config_schema:validate({ private_key_location = "/tmp/k.pem" })
  assert.is_falsy(ok)
  assert.is_truthy(err.keyid)
end)
```

Build the valid/invalid configs entirely from the spec's Configuration schema requirement. Emit rejection tests at the granularity the spec's scenarios define (typically one roll-up for required fields, one for enumerated fields, one per plugin-authored validation rule) plus acceptance of a canonical valid config — do not add one test per field beyond what the scenarios enumerate.

## Fixtures (signing keys etc.)

Shared fixtures are repo infrastructure, committed once and reused — never regenerate or invent per-plugin variants. Location: `testsuite/local/kong/fixtures/keys/`, which the compose stack mounts at `/tmp/kong/fixtures/keys/` inside every Kong container (config values must use the in-container path). Do **not** reuse `testsuite/local/kong/cluster.key`/`cluster.crt` — those are Kong clustering certs.

If a scenario needs signing keys and the key files are missing, create them in this run (directory already exists):

```sh
cd testsuite/local/kong/fixtures/keys
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out rsa-2048.pem
openssl pkey -in rsa-2048.pem -pubout -out rsa-2048.pub.pem
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out ec-p256.pem
openssl pkey -in ec-p256.pem -pubout -out ec-p256.pub.pem
```

Add a matching `<name>.jwks.json` per public key (`kid` = file stem) when a scenario needs JWKS, and a `keys/README.md` recording exactly how every file was generated. Generate ephemeral keys inside a test only when a scenario truly requires a key that must differ from the shared ones.

**JWKS URLs**: claim-content assertions may use a dummy `jwks_uri` value. When a scenario requires a *reachable* JWKS URL, reference the harness static path — already wired; do **not** edit `docker-compose.yml` or nginx for this:

- From Kong / compose network: `http://kong:8000/__fixtures__/keys/<name>.jwks.json`
- From host / Playwright: `${KONG_PROXY_URL}/__fixtures__/keys/<name>.jwks.json`

Never serve JWKS through a Kong route (the data plane deadlocks proxying to itself).

## Interop (producer/consumer plugins)

When the spec has an **Interop / shared contract** section and the peer plugin's spec exists:

- Write exactly one shared E2E file, `testsuite/tests/interop/<producer>-<consumer>.spec.ts`, asserting the contract as stated in the **producer's** spec (the source of truth).
- Do not duplicate either plugin's isolated scenario matrix there, and do not copy interop assertions into the per-plugin folders.

If the peer spec does not exist yet, note `interop deferred — <peer> spec not yet available` in the summary.

## Running the suites

Stack (from `testsuite/`; add `-f docker-compose-keycloak.yml` only if the plugin needs Keycloak):

```sh
KONG_VERSION=3.9.1 docker compose -f docker-compose.yml up -d --build
```

Playwright (from `testsuite/`; `npm ci` first time):

```sh
npx playwright test tests/plugins/<plugin> tests/interop
```

Busted (from the repo root; per plugin):

```sh
docker build -f Dockerfile.busted -t kong:busted .   # once
docker run --rm -v "$(pwd)":/work -w /work/plugins/<plugin> -u root \
  kong:busted sh -c 'luarocks make && busted'
```

## Failure policy

When a test fails against the running stack:

1. First suspect the test: helper bugs, missing readiness probe, wrong fixture path, misread spec. Fix and re-run.
2. If the assertion faithfully encodes the scenario's THEN and still fails: **keep the test asserting the spec**. Do not weaken the assertion, do not add `test.fail`, do not read plugin source to "understand", and do not edit the spec. Report the ID under `failing — spec/implementation mismatch` in the summary with the observed behavior. Peer review decides whether it's a spec fix, a plugin bug, or a `pending` tag + ticket.

## Assertion anti-patterns

Reject these in your own output — they look like coverage but catch nothing:

| Anti-pattern | Smell | Do instead |
|---|---|---|
| Presence-only | `toBeDefined()` / "header exists" with no value or shape | Assert the value the scenario names (exact header string, claim contents, status code, digest prefix, …) |
| Existence-only | One happy path where sibling scenarios enumerate a family of cases | Cover each distinct WHEN the scenarios enumerate; invent nothing beyond the spec |
| Positive-only | Only "good config / good request succeeds" | For rejection/no-op scenarios, assert the failure **and** the absence of side effects (no leaked headers, unchanged echo, …) |
| Incomplete negatives | Assert the status code but ignore the other THEN bullets | Assert **all** observable outcomes the scenario lists (status **and** headers **and** body/claims) |
| Placeholder | `assert.True(true)`, "schema loaded", `typeof x === "object"` | Delete or rewrite; every test exercises the scenario's behavior |
| Wrong layer | Unit-testing a PDK wrapper; Playwright-round-tripping a seamed pure helper | Follow the harness placement rules |

## Never do

- Read plugin source, `coverage.md`, or existing test suites during generation
- Write tests for out-of-scope bullets, or invent requirements for uncovered surfaces
- Soften quirk assertions, or use skip mechanisms for `pending` scenarios
- Sleep without a condition instead of calling `waitForRouteReady`
- Reimplement the readiness probe in a plugin helper (use `waitForRouteReady` from `helpers/kong.ts`)
- Hardcode Admin/Proxy host:port in plugin helpers (import `KONG_ADMIN_URL` / `KONG_PROXY_URL` from `helpers/kong.ts`)
- Modify plugin source, the spec, or the behavior of existing shared helpers
- Edit `docker-compose.yml` or nginx to serve fixtures / JWKS (harness already exposes `/__fixtures__/`)
- Duplicate interop assertions into per-plugin folders
- Work around a missing seam (reading source, second Kong stack, soft asserts) — report `blocked — needs seam`
- Ship a `[Verifies:]` citation whose test doesn't assert that scenario's specific THENs
- Leave clean-room enabled after the run — always run `clean-room-off.sh` before finishing (clears the flag and Cursor ignore block)

## Generation summary (final report)

```markdown
## Test generation summary — <plugin>
- Spec: openspec/specs/<plugin>/spec.md — <N> requirements, <M> scenarios
- Clean-room: on for run, off after (or note if still on)
- Files written: <busted specs, playwright specs, helper, interop, fixtures>
- Legacy tests deleted: <paths, or "none">
- Coverage: <M-k>/<M> scenario IDs cited
  - xfail (pending): <ids + tickets, or "none">
  - blocked — needs seam: <ids, or "none">
  - deferred — process-global-env: <ids, or "none">
  - failing — spec/implementation mismatch: <ids + one-line observed behavior, or "none">
  - interop: <covered | deferred — <peer> spec not yet available | n/a>
- Suite results: busted <pass/fail counts>, Playwright <pass/fail counts>
```
