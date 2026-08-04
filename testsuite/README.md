# Test suite

Automated tests for the Kong plugins in this repo run on a dual harness:

- **Playwright** (this directory) — integration/E2E tests against a dockerized Kong stack; the home for externally observable behavior (headers, status codes, claims, interop flows)
- **busted** (`plugins/<plugin>/spec/`) — unit and config-schema tests, run under OpenResty inside the pinned Kong image

Plugin tests are generated from behavioral specs (`openspec/specs/<plugin>/spec.md`, produced by the [`reverse-spec`](../.claude/skills/reverse-spec/SKILL.md) skill) in a clean-room agent session driven by the [`spec-to-test`](../.claude/skills/spec-to-test/SKILL.md) skill. That skill is the single source of truth for test structure, tagging, fixtures, and layout.

## Layout

```text
openspec/specs/<plugin>/spec.md        # normative behavior (+ stable scenario IDs)
openspec/specs/<plugin>/coverage.md    # spec-review aid only

plugins/<plugin>/spec/*_spec.lua       # busted unit/schema tests
plugins/<plugin>/.busted               # busted config (resty runner, gtest output)
plugins/_testlib/xfail.lua             # shared expected-failure helper (created on first need)

testsuite/helpers/kong.ts              # shared Admin API provisioning + waitForRouteReady
testsuite/helpers/upstream.ts          # local httpbun upstream defaults
testsuite/helpers/<plugin>.ts          # plugin-specific provisioning/fixtures
testsuite/local/kong/fixtures/         # shared signing keys / JWKS (also at /__fixtures__/ via nginx)
testsuite/tests/plugins/<plugin>/      # isolated Playwright tests
testsuite/tests/interop/               # shared producer↔consumer E2E
```

## The stack

`docker-compose.yml` (project `e2e`) runs Kong in CP/DP mode with the plugins baked into the `kong:e2e` image at build time:

- `kong-cp` — Admin API at http://localhost:8001 (`kong.localtest.me:8001` in-network)
- `kong-dp` — 3 data-plane replicas, fronted by an nginx load balancer (`kong` service) at http://localhost:8000
- `httpbun` — local echo upstream (`upstream.localtest.me:80` in-network) for observing proxied requests/responses
- Static fixtures — nginx serves `local/kong/fixtures/` at `http://kong:8000/__fixtures__/…` (reachable JWKS without a Kong route)
- `postgres`, `deck`, `kong-session-store` — supporting services
- `docker-compose-keycloak.yml` adds Keycloak (http://localhost:9081) for OIDC/JWT plugins

Playwright helpers read `KONG_ADMIN_URL` / `KONG_PROXY_URL` (defaults: `http://kong.localtest.me:8001` and `:8000`). After Admin API provisioning, call `waitForRouteReady` from `helpers/kong.ts` so all DP replicas have the route before asserting. Compose sets both URLs for the `playwright` service; override via env or `.env.e2e` when needed.

Bring it up (Keycloak overlay only when the plugins under test need it):

```sh
cd testsuite

KONG_VERSION=3.9.1 KC_VERSION=26.5.3 \
docker compose \
  -f docker-compose.yml \
  -f docker-compose-keycloak.yml \
  up -d --build
```

Plugin source changes require rebuilding `kong:e2e` (`--build`).

## Running Playwright tests

**Host** (recommended locally — uses your working tree). Stack must already be up. From `testsuite/` after `npm ci`:

```sh
npx playwright test                          # full suite
npx playwright test tests/plugins/<plugin>   # one plugin
npm run test:ui                              # interactive UI mode
```

**Container** (CI-shaped). Specs/helpers are copied into `playwright:e2e` at build time, so rebuild that image after test changes:

```sh
KONG_VERSION=3.9.1 KC_VERSION=26.5.3 \
docker compose --profile tests \
  -f docker-compose.yml -f docker-compose-keycloak.yml \
  build playwright
```

Then, with the stack already up:

```sh
# full suite
KONG_VERSION=3.9.1 KC_VERSION=26.5.3 \
docker compose --profile tests \
  -f docker-compose.yml -f docker-compose-keycloak.yml \
  run --rm playwright

# one plugin — pass the full command
KONG_VERSION=3.9.1 KC_VERSION=26.5.3 \
docker compose --profile tests \
  -f docker-compose.yml -f docker-compose-keycloak.yml \
  run --rm playwright \
  npx playwright test tests/plugins/<plugin>
```


## Running busted tests

Per plugin, from the repo root, inside the pinned Kong image. Prefer the prebaked `kong:busted` image so apt + busted are not reinstalled every run:

```sh
# once
docker build -f Dockerfile.busted -t kong:busted .

# each run — only luarocks make + busted
docker run --rm -v "$(pwd)":/work -w /work/plugins/<plugin> -u root \
  kong:busted sh -c 'luarocks make && busted'
```

For a tighter edit/test loop, leave a shell open:

```sh
docker run -it --rm -v "$(pwd)":/work -u root -w /work kong:busted bash
# then after each edit:
cd plugins/<plugin> && luarocks make && busted
```

Each plugin with busted tests carries a `.busted` config pointing at `spec/resty-runner.lua`, which re-execs busted under `resty` so Kong/OpenResty modules are available. `luarocks make` installs the plugin from its rockspec so `require("kong.plugins.<plugin>…")` resolves (re-run it after source edits).

## Test semantics (summary)

- Every test cites the spec scenario it verifies: `[Verifies: <plugin>.<requirement>.<scenario>]`.
- Scenarios tagged `pending — <ticket>` in the spec are expected failures: Playwright `test.fail(...)` (or the busted `xfail` helper). They run, must fail, and an unexpected pass (XPASS) fails the job — signaling the fix landed and the annotation + spec tag should be removed together.
- Untagged and `quirk` scenarios are hard asserts; failures fail the job.

## CI

### Current state

`.github/workflows/test.yaml` runs both harnesses on pushes to `main`/`feature/*`, PRs into those branches, and `workflow_dispatch`:

- **Playwright** — full containerized suite (Kong 3.9.1 × Keycloak 26.5.3); uploads HTML/JSON reports; comments on the PR (or opens an issue on `push`) on unexpected failures
- **Busted** — full matrix over every plugin with `plugins/<plugin>/spec/*_spec.lua`, inside `kong:busted` (`luarocks make && busted`)

```text
build-busted-image  → list plugins with busted specs; docker build -f Dockerfile.busted
busted (matrix)     → per plugin: luarocks make && busted
plugin-tests        → full Playwright suite
```

Fail the workflow on any busted failure or Playwright unexpected failure / unexpected pass (`test.fail` XPASS).

### Target state

Path-filtered jobs plus a long-lived `dev` branch (aligned with other APS repos):

| Change | What runs |
|---|---|
| PR `feature/*` → `dev` | Affected plugins only (see below) |
| PR `dev` → `main` | Full busted matrix + full Playwright suite (Kong × Keycloak matrix as applicable) |
| `workflow_dispatch` / push to `main` | Full suite |

Until `dev` exists, the same path-filtered jobs can run on PRs into the current default branch, keeping a full-suite job on `main`.

#### Affected-plugin detection (`feature/*` → `dev`)

A plugin `P` is affected when the PR touches any of:

- `plugins/P/**`
- `testsuite/tests/plugins/P/**`
- `testsuite/helpers/P.ts`
- `openspec/specs/P/**`

Additionally:

- Run `testsuite/tests/interop/X-Y.spec.ts` when `X` or `Y` is affected (or the interop file itself changes)
- Shared infrastructure changes (`testsuite/helpers/kong.ts`, `testsuite/helpers/upstream.ts`, `testsuite/docker-compose*.yml`, `testsuite/local/kong/fixtures/**`, `.github/workflows/test*.yml`) trigger the **full** Playwright + busted suites

#### Job shape

```text
detect-changes  → outputs: plugins[], run_full, interop[]
busted          → matrix over plugins[] (or all plugins if run_full)
playwright      → path filter tests/plugins/<p> + interop files
                  (or full suite if run_full)
```
