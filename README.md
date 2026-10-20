# Kong (OSS) Community Plugins

## Testing

See [testsuite/README.md](testsuite/README.md) for the full testing guide: running the docker compose stack, executing Playwright and busted tests, spec-driven test generation, and the CI strategy.

Quickstart (for `Kong v.3.9.1` and `Keycloak v.26.5.3`):

```sh
cd testsuite

KONG_VERSION=3.9.1 KC_VERSION=26.5.3 \
docker compose \
  -f docker-compose.yml \
  -f docker-compose-keycloak.yml \
  up -d --build
```

- Admin: http://localhost:8001
- Proxy: http://localhost:8000

## Development

If you are using Visual Studio Code, we recommend you install the `vscode-lua` extension.

### Linting and static analysis

```sh
docker run -ti --rm -v `pwd`:/work -w /work ubuntu:latest /bin/bash

apt-get update && apt-get install -y lua5.4 luarocks

luarocks install luacheck

```

Run luacheck against each plugin

```sh
declare -a arr=("jwt-keycloak" "oidc" "oidc-consumer")

for plugin in "${arr[@]}"
do
  echo ""
  echo "---------------------------------------------------------------------"
  echo "Checking ${plugin}"
  echo "---------------------------------------------------------------------"
  cd /work/plugins/$plugin
  luacheck src \
  --new-globals kong --new-globals ngx \
  --no-unused-args \
  --no-redefined
done

```

### Running Kong in dbless mode

```sh
docker run -ti --rm \
  --env-file ./local/kong/.env.local.dbless \
  -p 8007:8001 \
  --name kong kong:e2e
```

### Running tests with busted

See [testsuite/README.md](testsuite/README.md#running-busted-tests). For a fast local loop, build once then re-run:

```sh
docker build -f Dockerfile.busted -t kong:busted .

docker run --rm -v "$(pwd)":/work -w /work/plugins/jwt-keycloak -u root \
  kong:busted sh -c 'luarocks make && busted'
```

## Releases

This repository has one release version for all plugins, tagged `vX.Y.Z`. Individual plugins do not receive separate release tags; release notes group changes by plugin and list repository/tooling changes. Existing LuaRocks rockspec versions are preserved.

Feature/dev builds run the existing Busted and integration tests. Feature PRs into dev request squash auto-merge after required checks/reviews. Promote dev to main with a reviewed merge-commit PR and exactly one `release=major`, `release=minor` or `release=patch` label. The release workflow validates the label and, on merge, uses the standard `semver` CLI to increment the latest repository version and `gh release create` to tag the exact merged commit and publish notes. GitHub supplies source archives.

Historical `vX.Y.Z-N` tags remain unchanged; their base version is used when calculating the next stable release. For example, a patch promotion after `v1.5.0-1` produces `v1.5.1`. Retries reuse a stable tag already pointing at the merged commit. Tags are not moved.

The SDX edge image consumes the release tag through `KONG_PLUGINS_REF`, with its resolved commit verified by `KONG_PLUGINS_REVISION`. Update the default dependency through a reviewed aps-devops PR; edge publication then releases its chart.

Promote one PR at a time, and resolve a failed release before the next promotion; GitHub concurrency is not a durable queue. dev and main require reviews and passing tests; squash merges go into dev and merge commits into main.
