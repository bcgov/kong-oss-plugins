ARG KONG_VERSION="3.9.0"
FROM docker.io/kong:${KONG_VERSION}

USER root

RUN if [ -x "$(command -v apk)" ]; then apk add --no-cache unzip curl; \
    elif [ -x "$(command -v apt-get)" ]; then apt-get update && apt-get -y install unzip curl; \
    fi

WORKDIR /build

COPY plugins/trust-registry-ai plugins/trust-registry-ai

RUN cd plugins/trust-registry-ai && luarocks make kong-plugin-trust-registry-ai-1.0.0-0.rockspec

USER kong
WORKDIR /
