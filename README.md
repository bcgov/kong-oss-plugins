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
