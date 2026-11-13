# ADR 0001: Consolidate trust-registry and use OpenSpec behavioral contracts

- Status: Accepted
- Date: 2026-11-11
- Context: APS-4312, PR #59; OpenSpec experiment merged through PR #63

## Context

The JWKS endpoint experiment produced Spec-Kit (`trust-registry-ai`) and OpenSpec (`trust-registry-ai-openspec`) implementations alongside the existing `trust-registry`. Maintaining three plugin names and competing specifications makes the supported behavior unclear.

The experiment report dated 2026-05-19 described a lighter OpenSpec workflow and fewer planning artifacts than Spec-Kit. Its reported costs were approximately $2.00 and $3.98 respectively for those individual sessions, not a general benchmark. Neither initial workflow produced automated tests without an explicit request. Spec-Kit initially generated manual PEM conversion; the refined implementations all delegated public JWK export to OpenSSL. The experiment remains available in PR #59's earlier commits, including 779fc24, and PR #63.

The repository subsequently adopted reverse-spec and spec-to-test skills for trust-sign, trust-verify-signature, mtls-auth, mtls-acl, and token-exchange. These use per-plugin behavioral specifications, stable scenario IDs, coverage review maps, and isolated test generation.

## Decision

Keep `plugins/trust-registry/` as the sole implementation and public plugin name. Preserve its optional `config.key_set`, named URI capture precedence, native public PEM-to-JWK conversion, and plugin-log integration. Remove both experimental implementations, Spec-Kit configuration and commands, duplicate experiment specifications, and the separate validation stack.

Use `openspec/specs/trust-registry/spec.md` as the normative behavioral contract and `coverage.md` as a non-normative review aid. Generate schema/helper tests with Busted and wire-level tests with Playwright in a fresh clean-room session using the repository skills. Tests cite stable scenario IDs and reuse the shared Kong harness and fixture keys.

## Consequences

There is one supported `trust-registry` plugin and one normative behavioral specification. The plugin publishes only public RSA, EC, and OKP parameters and supported JWK metadata. It omits symmetric, unsupported, and malformed individual keys, returns an array for empty results, and returns generic JSON 500 responses on database failures without partial results or upstream fall-through. Unknown keysets return 404.

Busted tests use an injected DAO collection helper to exercise persistence failures and malformed entities that Kong Admin validation prevents creating. Playwright tests verify the public HTTP contract against the shared Kong stack. Tests assert the specified behavior and cite stable scenario IDs.

OpenSpec is the supported specification workflow. Architectural decisions belong in ADRs rather than a second planning system. Changes to plugin behavior update the normative specification and its tests together.
