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
