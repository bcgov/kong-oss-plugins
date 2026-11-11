# Kong OSS Plugins Repository - Copilot Instructions

## Repository Overview

This repository contains 18 custom Kong Gateway plugins for authentication, authorization, and security functions. Primary languages: Lua (82 files, ~45MB total). Target runtime: Kong Gateway 2.x and 3.x with OpenResty/nginx.

**Plugins**: dpop, jwt-keycloak, mtls-acl, mtls-auth, oidc, oidc-consumer, openid-authzen, response-signer, token-exchange, trust-hello, trust-jwks, trust-kms, trust-ledger, trust-registry, trust-sign, trust-timestamp, trust-verify-digest, trust-verify-signature

## Repository Structure

```
/plugins/              # All plugin source code
  /<plugin-name>/
    /src/              # Lua source files (handler.lua, schema.lua, etc.)
    /spec/             # Busted unit tests (if present)
    *.rockspec         # LuaRocks package specification
/testsuite/            # E2E Playwright tests
  /tests/              # TypeScript test files
  /helpers/            # Test utilities
  /local/              # Docker config (Kong, Keycloak, Postgres)
  docker-compose.yml   # Main test infrastructure
  package.json         # NPM dependencies for Playwright
/Dockerfile            # Kong image with all plugins installed
/.github/workflows/    # CI/CD pipelines
  test.yaml            # Playwright E2E test workflow
```

## Plugin Structure

Each Kong plugin follows this standard structure:
- `src/handler.lua` - Plugin lifecycle hooks (access, header_filter, etc.)
- `src/schema.lua` - Configuration validation schema
- `kong-plugin-<name>-<version>.rockspec` - Package metadata and build configuration

The `oidc` plugin has version-specific dependencies:
- Kong 2.x: `kong-plugin-oidc-deps-k2-1.5.0-2.rockspec`
- Kong 3.x: `kong-plugin-oidc-deps-k3-1.5.0-2.rockspec`

## Build and Test Process

### Prerequisites
- Docker and docker compose (required for all builds and tests)
- Node.js/npm (only for running Playwright tests locally)
- Lua 5.4 and luarocks (only for local linting, not required for builds)

### Building the Kong Docker Image

**ALWAYS build from the repository root, not from testsuite directory.**

```bash
# Build Kong image with all plugins (takes ~22 seconds)
docker build -t kong:e2e --build-arg KONG_VERSION=3.9.1 -f Dockerfile .
```

This builds a Kong image with all 18 plugins installed via luarocks. The build process:
1. Pulls the official Kong base image
2. Installs each plugin using `luarocks make` in each plugin directory
3. Sets the `KONG_PLUGINS` environment variable to include all custom plugins

**NOTE**: The oidc plugin has special handling - it installs different dependencies based on Kong version (2.x vs 3.x).

### Building Test Infrastructure

```bash
cd testsuite

# Build all test images including Kong, Keycloak, and Playwright (takes ~22 seconds)
KONG_VERSION=3.9.1 KC_VERSION=26.5.3 \
docker compose \
  -f docker-compose.yml \
  -f docker-compose-keycloak.yml build
```

**Supported versions**:
- Kong: 3.9.1
- Keycloak: 26.5.3

### Running E2E Tests

**Method 1: Headless (CI mode)**

```bash
cd testsuite

# Install npm dependencies first (only needed once)
npm install

# Run full test suite with Docker Compose
KONG_VERSION=3.9.1 KC_VERSION=26.5.3 \
docker compose --profile tests \
  -f docker-compose.yml \
  -f docker-compose-keycloak.yml up
```

This starts all services (Kong CP/DP, Postgres, Redis, Keycloak, deck) and runs Playwright tests in a container. Tests complete automatically when the `playwright` container exits.

**Method 2: Interactive (UI mode)**

```bash
cd testsuite

# Start Kong and Keycloak without tests
KONG_VERSION=3.9.1 KC_VERSION=26.5.3 \
docker compose \
  -f docker-compose.yml \
  -f docker-compose-keycloak.yml up

# In another terminal, run Playwright UI
npm run test:ui
```

**Services exposed**:
- Kong Admin API: http://localhost:8001
- Kong Proxy: http://localhost:8000
- Keycloak: http://localhost:9081

### Linting Lua Code

Linting is **not** automated in CI but can be run manually. The process requires a Docker container with Lua and luarocks:

```bash
# Start Ubuntu container
docker run -ti --rm -v $(pwd):/work -w /work ubuntu:latest /bin/bash

# Inside container: Install dependencies (takes ~60 seconds)
apt-get update && apt-get install -y lua5.4 luarocks
luarocks install luacheck

# Lint a specific plugin
cd /work/plugins/jwt-keycloak
luacheck src \
  --new-globals kong --new-globals ngx \
  --no-unused-args \
  --no-redefined

# Lint all plugins
declare -a arr=("jwt-keycloak" "oidc" "oidc-consumer" "dpop" "mtls-auth" "mtls-acl" "openid-authzen" "response-signer" "token-exchange" "trust-hello" "trust-jwks" "trust-kms" "trust-ledger" "trust-registry" "trust-sign" "trust-timestamp" "trust-verify-digest" "trust-verify-signature")

for plugin in "${arr[@]}"; do
  echo "Checking ${plugin}"
  cd /work/plugins/$plugin
  luacheck src \
    --new-globals kong --new-globals ngx \
    --no-unused-args \
    --no-redefined
done
```

**IMPORTANT**: Must use `--new-globals kong --new-globals ngx` to avoid false positives for Kong PDK and OpenResty globals.

### Running Unit Tests (Busted)

Only `jwt-keycloak` and `trust-verify-digest` have Busted unit tests. Example for jwt-keycloak:

```bash
# Start OpenResty container
docker run -ti --rm --net=host -v $(pwd):/work -w /work \
  openresty/openresty:focal /bin/bash

# Inside container: Install dependencies
apt-get update && apt-get install -y libssl-dev
luarocks install busted
luarocks install LuaSocket
luarocks install luasec
luarocks install kong --deps-mode none

# Run tests
cd /work/plugins/jwt-keycloak
luarocks build
busted
```

## CI/CD Pipeline

### GitHub Actions Workflow (`.github/workflows/test.yaml`)

**Trigger**: Push to `main` or `feature/*` branches, or manual workflow dispatch

**Strategy**: Matrix testing across Kong (`3.9.1`) and Keycloak (`26.5.3`)

**Steps**:
1. Build Docker images (~22s)
2. Start all services with `docker compose up -d`
3. Stream logs and wait for `playwright` container to exit
4. Upload HTML test report as artifact
5. Parse results JSON and create GitHub issue if any tests fail

**Critical environment variables**:
- `KONG_VERSION`: Kong version to test (e.g., 3.9.1)
- `KC_VERSION`: Keycloak version (e.g., 26.5.3)
- `CI=true`: Enables CI mode for Playwright (disables parallel workers, enables retries)

**Test results location**:
- JSON: `testsuite/playwright-results/test-results.json`
- HTML: `testsuite/playwright-report/index.html`

## Common Pitfalls and Solutions

### Docker Compose Issues

1. **ALWAYS use environment variables for versions**:
   ```bash
   KONG_VERSION=3.9.1 KC_VERSION=26.5.3 docker compose ...
   ```
   Without these, defaults may not match your needs.

2. **Include the Keycloak overlay**:
   ```bash
   -f docker-compose.yml -f docker-compose-keycloak.yml
   ```

3. **Clean up containers between test runs**:
   ```bash
   docker compose --profile tests \
     -f docker-compose.yml \
     -f docker-compose-keycloak.yml down
   ```

### Plugin Development

1. **Plugin naming convention**: Use `kong-plugin-<name>` for package name in rockspec

2. **Dependencies differ by Kong version**: The `oidc` plugin shows the pattern:
   - Use conditional dependencies in rockspec or separate rockspec files
   - Kong 2.x and 3.x may need different library versions

3. **Global variables**: Kong PDK (`kong.*`) and OpenResty (`ngx.*`) are injected at runtime. Don't declare them; use linter flags to suppress warnings.

4. **Handler methods**: Common lifecycle hooks are `init_worker`, `access`, `header_filter`, `body_filter`, `log`

### Testing

1. **Test file location**: Playwright tests go in `testsuite/tests/plugins/<plugin-name>/*.spec.ts`

2. **Playwright configuration**: In `testsuite/playwright.config.ts`:
   - Tests run sequentially in CI (`fullyParallel: false`)
   - 2 retries on CI, 0 locally
   - Single worker on CI to avoid race conditions

3. **Service dependencies**: The docker-compose setup uses health checks and dependency ordering:
   - Postgres → kong-migrations → kong-migrations-up → kong-cp → kong-dp → kong (nginx) → deck → playwright
   - All must be healthy/completed before tests run

## Making Code Changes

### Adding a New Plugin

1. Create directory: `plugins/<plugin-name>/`
2. Add `src/handler.lua` with Kong plugin structure
3. Add `src/schema.lua` for configuration validation
4. Create `kong-plugin-<name>-<version>.rockspec` with build configuration
5. Update `Dockerfile` to add `RUN (cd plugins/<plugin-name> && luarocks make)`
6. Update `KONG_PLUGINS` environment variable in `Dockerfile`
7. Add E2E tests in `testsuite/tests/plugins/<plugin-name>/`

### Modifying Existing Plugin

1. Edit Lua source files in `plugins/<plugin-name>/src/`
2. Rebuild Kong image: `docker build -t kong:e2e --build-arg KONG_VERSION=3.9.1 -f Dockerfile .`
3. Rebuild test infrastructure: `cd testsuite && KONG_VERSION=3.9.1 KC_VERSION=26.5.3 docker compose -f docker-compose.yml -f docker-compose-keycloak.yml build`
4. Run E2E tests to validate changes
5. Run luacheck to ensure code quality

### Key Files to Know

- `testsuite/local/kong/kong.yaml` - Declarative Kong configuration (deck format)
- `testsuite/local/kong/.env.local` - Kong control plane environment variables
- `testsuite/local/kong/.env.dp.local` - Kong data plane environment variables
- `testsuite/helpers/e2e-test.ts` - Shared E2E test logic
- `plugins/jwt-keycloak/src/handler.lua` - Example handler with TODO comment about PDK wrapper

## Validation Checklist

Before submitting code changes:

1. ✅ Build Kong image successfully (`docker build ...`)
2. ✅ Run luacheck on modified plugins (no errors)
3. ✅ Build test infrastructure (`docker compose ... build`)
4. ✅ Run E2E tests and verify all pass
5. ✅ Check test results in `testsuite/playwright-results/test-results.json`
6. ✅ Review any warnings in `testsuite/playwright-report/index.html`

## Important Notes

- **Never modify node_modules**: It's gitignored for a reason. Run `npm install` to regenerate.
- **Docker is required**: There is no non-Docker build path. All builds use containers.
- **Kong version matters**: Some plugins behave differently on Kong 2.x vs 3.x. Test both if making core changes.
- **Playwright tests are slow**: Full suite can take 5-10 minutes. Run specific tests during development: `npm test -- tests/plugins/oidc/default.spec.ts`
- **Trust the instructions**: If build/test commands above work, use them exactly as documented. The repository structure is stable and well-tested.

**If you encounter issues not covered here, check:**
1. README.md for latest documentation
2. .github/workflows/test.yaml for CI configuration
3. Plugin-specific README in `plugins/<name>/README.md`
4. Existing tests in `testsuite/tests/` for examples
