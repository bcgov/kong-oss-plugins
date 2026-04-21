ARG KONG_VERSION="3.9.1"
FROM docker.io/kong:${KONG_VERSION}

USER root

# some logic to handle different base kong image starting in 3.2
RUN if [ -x "$(command -v apk)" ]; then apk add --no-cache unzip curl; \
    elif [ -x "$(command -v apt-get)" ]; then apt-get update && apt-get -y install unzip curl; \
    fi

WORKDIR /build

COPY plugins plugins

RUN (cd plugins/oidc && luarocks make kong-plugin-oidc-1.5.0-2.rockspec)
RUN (cd plugins/oidc && \
    case "${KONG_VERSION}" in \
        (3*) luarocks build --deps-only kong-plugin-oidc-deps-k3-1.5.0-2.rockspec;; \
        (*)  luarocks build --deps-only kong-plugin-oidc-deps-k2-1.5.0-2.rockspec;; \
    esac)
RUN (cd plugins/oidc-consumer && luarocks make)

RUN (cd plugins/dpop && luarocks make)
RUN (cd plugins/jwt-keycloak && luarocks make)
RUN (cd plugins/mtls-auth && luarocks make)
RUN (cd plugins/mtls-acl && luarocks make)
RUN (cd plugins/openid-authzen && luarocks make)
RUN (cd plugins/response-signer && luarocks make)
RUN (cd plugins/token-exchange && luarocks make)
RUN (cd plugins/trust-hello && luarocks make)
RUN (cd plugins/trust-jwks && luarocks make)
RUN (cd plugins/trust-kms && luarocks make)
RUN (cd plugins/trust-ledger && luarocks make)
RUN (cd plugins/trust-registry && luarocks make)
RUN (cd plugins/trust-sign && luarocks make)
RUN (cd plugins/trust-timestamp && luarocks make)
RUN (cd plugins/trust-verify-digest && luarocks make)
RUN (cd plugins/trust-verify-signature && luarocks make)
RUN (cd plugins/trust-registry-ai && luarocks make kong-plugin-trust-registry-ai-1.0.0-0.rockspec)

USER kong
WORKDIR /

ENV KONG_PLUGINS="bundled, dpop, jwt-keycloak, oidc, oidc-consumer, mtls-auth, mtls-acl, openid-authzen, response-signer, token-exchange, trust-hello, trust-jwks, trust-kms, trust-ledger, trust-registry, trust-sign, trust-timestamp, trust-verify-digest, trust-verify-signature, trust-registry-ai"
