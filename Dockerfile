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
RUN (cd plugins/oidc && luarocks make kong-plugin-oidc-1.5.0-2.rockspec)
RUN (cd plugins/oidc && \
    if [[ ${KONG_VERSION} == 3* ]]; then luarocks build --deps-only kong-plugin-oidc-deps-k3-1.5.0-2.rockspec; \
    else luarocks build --deps-only kong-plugin-oidc-deps-k2-1.5.0-2.rockspec; \
    fi)
RUN (cd plugins/oidc-consumer && luarocks make)

USER kong
WORKDIR /

ENV KONG_PLUGINS="bundled, jwt-keycloak, oidc, oidc-consumer"
