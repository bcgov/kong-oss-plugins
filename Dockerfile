ARG KONG_VERSION="3.9.0"
FROM docker.io/kong:${KONG_VERSION}

USER root

# some logic to handle different base kong image starting in 3.2
RUN if [ -x "$(command -v apk)" ]; then apk add --no-cache unzip; \
    elif [ -x "$(command -v apt-get)" ]; then apt-get update && apt-get -y install unzip; \
    fi

WORKDIR /build

COPY plugins plugins

RUN (cd plugins/jwt-keycloak && luarocks make)
RUN (cd plugins/oidc && luarocks make)
RUN (cd plugins/oidc-consumer && luarocks make)

USER kong
WORKDIR /

ENV KONG_PLUGINS="bundled, jwt-keycloak, oidc, oidc-consumer"
