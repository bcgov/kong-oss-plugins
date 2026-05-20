ARG KONG_VERSION="3.9.0"
FROM docker.io/kong:${KONG_VERSION}

USER root

RUN if [ -x "$(command -v apk)" ]; then apk add --no-cache unzip curl; \
    elif [ -x "$(command -v apt-get)" ]; then apt-get update && apt-get -y install unzip curl; \
    fi

WORKDIR /build

COPY plugins/trust-registry-ai-openspec plugins/trust-registry-ai-openspec

RUN cd plugins/trust-registry-ai-openspec && luarocks make kong-plugin-trust-registry-ai-openspec-1.0.0-0.rockspec

USER kong
WORKDIR /
