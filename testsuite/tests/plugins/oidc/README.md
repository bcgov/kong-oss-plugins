# oidc testing

## Scope

### TODO

- default.spec.ts : try and prove tests that are setup
- introspection
- bearer_jwt_auth

  - bearer_jwt_auth_allowed_auds: null,
  - bearer_jwt_auth_enable: "no",
  - bearer_jwt_auth_signing_algs: ["RS256"],
  - bearer_only: "no",
  - skip_already_auth_requests: "no"

- groups_claim
- sessions (secret, secure, session*check*\*)
- logout (revoke token on logout, redirects)
- token info

- scope, validate_scope
- timeout
