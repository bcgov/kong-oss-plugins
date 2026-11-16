# Consolidate trust-registry specification and tests

## Why

PR #59 contains two experimental plugins and duplicate planning systems. Align it with the repository's established OpenSpec behavioral contracts and clean-room test generation.

## What changes

Keep existing trust-registry behavior, reverse-spec it with stable scenario IDs, generate Busted and Playwright coverage, remove the experiments and Spec-Kit tooling, and preserve the decision in ADR 0001. No runtime behavior change is proposed. Existing quirks and untestable fault-injection cases remain visible for review.

## Capabilities

- New: trust-registry behavioral specification and scenario-linked tests.
- Modified runtime capabilities: none.

## Impact

One public trust-registry plugin, the shared test stack, and the existing reverse-spec/spec-to-test skills. No independent validation stack or experimental plugin names remain.
