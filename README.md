# Kong (OSS) Community Plugins

## Testing

There are various configurations for testing to cover different versions of Keycloak and Kong.

### Running

#### Kong 2.x

For `Kong v.2.8.5` and `Keycloak v.15.1.1`, run the following:

```sh
cd testsuite

KONG_VERSION=2.8.5 KC_VERSION=15.1.1 \
docker compose \
  -f docker-compose.yml \
  -f docker-compose-keycloak-spring.yml build
```

```sh
KONG_VERSION=2.8.5 KC_VERSION=15.1.1 \
docker compose \
  -f docker-compose.yml \
  -f docker-compose-keycloak-spring.yml up
```

- Admin: http://localhost:8001
- Proxy: http://localhost:8000

#### Kong 3.x

For `Kong v.3.9.0` and `Keycloak v.15.1.1`, run the following:

```sh
cd testsuite

KONG_VERSION=3.9.0 KC_VERSION=15.1.1 \
docker compose \
  -f docker-compose.yml \
  -f docker-compose-keycloak-spring.yml build
```

```sh
KONG_VERSION=3.9.0 KC_VERSION=15.1.1 \
docker compose \
  -f docker-compose.yml \
  -f docker-compose-keycloak-spring.yml up
```

- Admin: http://localhost:8001
- Proxy: http://localhost:8000

### Playright Tests

```sh
npm run test:ui
```

To run the test suite headless, use docker compose:

```sh
KONG_VERSION=3.9.0 KC_VERSION=15.1.1 \
docker compose --profile tests \
  -f docker-compose.yml \
  -f docker-compose-keycloak-spring.yml up

```

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
  -p 8007:8007 \
  --name kong kong:e2e
```

### Running tests with busted

#### jwt-keycloak

```sh
docker run -ti --rm --net=host -v `pwd`:/work -w /work \
  openresty/openresty:focal /bin/bash

apt-get update && apt-get install -y libssl-dev

luarocks install busted
luarocks install LuaSocket
luarocks install luasec
luarocks install kong

luarocks install kong --deps-mode none

luarocks build

busted
```
