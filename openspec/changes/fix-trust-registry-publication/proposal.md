# Correct trust-registry publication and failure handling

## Why

The baseline can publish private JWK fields, serialize empty keysets incorrectly, conflate database errors with absence, fall through upstream on iterator failure, and abort on malformed stored JSON.

## What changes

Update the behavioral contract and preserve scenario IDs while correcting all five quirks. Add a public-field allowlist and safe JSON decode, explicit generic 500 responses, an array-preserving result, and a DAO-injected collection seam for fault tests. Preserve keyset-selection precedence and unknown-keyset 404 responses.

## Impact

trust-registry implementation, rockspec module registration, spec/coverage map, Busted fault/security tests and Playwright assertions.
