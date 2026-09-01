# Kong OSS Plugins

| Plugin                 | Purpose                                                                           |
| ---------------------- | --------------------------------------------------------------------------------- |
| dpop                   | Validates a Demonstration of Proof of Possession token                            |
| jwt-keycloak           | Validates a Bearer Token                                                          |
| mtls-acl               | Applies an allow/deny policy based on a configurable client certificate attribute |
| mtls-auth              | Sets request headers for various client certificate attributes                    |
| oidc                   | Performs the authorization code grant flow                                        |
| oidc-consumer          | Maps an authenticated user to a Kong Consumer                                     |
| pep                    | Calls an external policy decision engine using Authzen protocol                   |
| plugin-log             | Provides a common way for adding internal error details into the log              |
| response-signer        | Performs a signing function on the response message                               |
| token-exchange         | Interaction with a token endpoint for token exchange and introspection            |
| trust-jwks             | Verify a jwks document originated from the same domain TLS that it is hosted on   |
| trust-sign             | Builds an rfc-9421 HTTP Message Signature                                         |
| trust-registry         | Returns a JWKS document listing trusted public keys                               |
| trust-timestamp        | Calls a Timestamping Authority using the RFC-3161 Time-Stamp Protocol             |
| trust-ledger           | Log RFC-3161 message to an Immutable Ledger                                       |
| trust-verify-digest    | Verify that the content-digest matches the payload body                           |
| trust-verify-signature | Verifies the signed JWT manifest header produced by trust-sign                    |
