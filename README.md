# Kong (OSS) Community Plugins

## Testing

There are various configurations for testing to cover different versions of Keycloak and Kong.

For `Kong v.2.8.5` and `Keycloak v.15.1.1`, run the following:

### Build

```sh
KONG_VERSION=2.8.5 KC_VERSION=15.1.1 \
docker compose \
  -f docker-compose.yml \
  -f docker-compose-keycloak-spring.yml build
```

### Run

```sh
docker compose \
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
