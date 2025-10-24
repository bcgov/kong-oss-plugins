# Kong OSS Plugins

| Plugin          | Purpose                                                                           |
| --------------- | --------------------------------------------------------------------------------- |
| dpop            | Demonstration of Proof of Possession - validates a DPoP token                     |
| jwt-keycloak    | Validates a Bearer Token                                                          |
| mtls-acl        | Applies an allow/deny policy based on a configurable client certificate attribute |
| mtls-auth       | Sets request headers for various client certificate attributes                    |
| oidc            | Performs the authorization code grant flow                                        |
| oidc-consumer   | Maps an authenticated user to a Kong Consumer                                     |
| openid-authzen  | Calls an external policy decision engine using Authzen protocol                   |
| response-signer | Performs a signing function on the response message                               |
| token-exchange  | Interaction with a token endpoint for token exchange and introspection            |
| trust-sign      | Builds an rfc-9421 HTTP Message Signature                                         |
| trust-timestamp | Calls a Timestamping Authority using the RFC-3161 Time-Stamp Protocol             |
| trust-ledger    | Log RFC-3161 message to an Immutable Ledger                                       |
