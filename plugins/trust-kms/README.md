# Introduction

## Overview

The `trust-kms` plugin lets you perform key-management and signing operations against a Key Management Service (KMS) from inside Kong. It supports two backends:

- **`aws`** — AWS KMS (asymmetric `SIGN_VERIFY` keys, e.g. `ECC_NIST_P521`).
- **`local`** — a private key loaded from disk via the `KONG_SIGNING_CERT_KEY` / `KONG_SIGNING_CERT` environment variables.

The plugin can:

1. **Create a new asymmetric KMS key** and return a signed Certificate Signing Request (CSR), the public key (PEM and JWK), and the KMS key id.
2. **Counter-sign an edge token** (the JWS signature segment of a JWT presented on the request or response) using the configured KMS key, and emit the result as an `X-Entity-Sig` header.

### How it works

The plugin runs in one of two **directions** (`request` or `response`) and performs one of three **operations** (`create_key`, `sign`, `verify`).

**`create_key`**

- Reads a JSON body from the incoming request containing identity fields (`country`, `org_name`, `serial_number`, `common_name`, `san`, `requester_name`, `requester_email`).
- With the `aws` backend: calls `KMS:createKey` (and `createAlias`), fetches the public key with `KMS:getPublicKey`, builds a CSR, extracts the to-be-signed bytes, signs them with `KMS:sign`, and reassembles a fully-signed CSR in PEM form.
- With the `local` backend: loads the configured private key, builds and self-signs the CSR locally.
- Returns the `key_id`, signing algorithm, CSR (PEM), public key (PEM + JWK), and the input identity fields.

**`sign` (request or response direction)**

- Reads the edge token from the configured header (`config.signature_header_key`).
- Splits the token on `.` and takes the third (signature) segment.
- Counter-signs that segment with the KMS backend:
  - `aws`: retrieves the public key, requires a unique matching registration in `config.keyset_name`, and calls `KMS:sign` with the resolved key ARN and configured `signature_algorithm`.
  - `local`: requires exactly one public-key registration matching the private key in `config.keyset_name`, then signs the segment, verifies it round-trips, and base64url-encodes the result.
- Writes the signature into the `X-Entity-Sig` header on the request (`access` phase) or response (buffered `response` phase).

### Get started with the `trust-kms` plugin

Install the rock and enable the plugin on your Kong instance:

```sh
luarocks install kong-plugin-trust-kms
export KONG_PLUGINS=bundled,trust-kms
```

For the `aws` backend, the standard AWS environment variables / instance role apply (`AWS_REGION`, credentials, etc.).

For the `local` backend, point Kong at the signing material:

```sh
export KONG_SIGNING_CERT_KEY=/path/to/signing-private.pem
export KONG_SIGNING_CERT=/path/to/signing-cert.pem
```

For counter-signing with either backend, register the corresponding public key (PEM or JWK,
with a `kid`) in a Kong key set and set `config.keyset_name` to that set's name.
`config.private_key_location` can supply the private-key path when
`KONG_SIGNING_CERT_KEY` is absent. For example:

```yaml
plugins:
  - name: trust-kms
    config:
      direction: request
      operation: sign
      backend: local
      keyset_name: entity-signing-keys
      private_key_location: /path/to/signing-private.pem
      signature_header_key: X-Edge-Token
```

Both backends use trust-sign's shared `resolve_public_kid` lookup, including its
30-second registration cache keyed by key-set name and canonical public key.
Missing key sets, unmatched keys, ambiguous matches, or DAO
errors fail counter-signing with HTTP 500 without setting `X-Entity-Sig`.
For local signing, the same cached private-key bytes supply the public component
and the signature. Private-key
files are cached by path without expiry; restart Kong after replacing a key at
the same path. Registration changes can take up to 30 seconds to be observed.
For response signing, registration is checked during `access` and the validated
backend key is retained in `kong.ctx.plugin`. Counter-signing runs in Kong's
buffered `response` phase so AWS KMS network I/O is allowed. This enables
response buffering for services using the plugin; Kong's buffered proxy
limitations apply (including HTTP/2 or gRPC upstreams). See
[Kong handler phases](https://developer.konghq.com/custom-plugins/handler.lua/).
The matched `kid` validates registration; `X-Entity-Sig` remains a raw encoded
signature and does not carry a `kid`.

`KONG_SIGNING_CERT` is no longer needed for local counter-signing; the registered
public key replaces the mounted-certificate check. Local CSR creation still uses
the certificate.

## Configuration reference

### Configuration

Enable the plugin on a Service (for example, counter-signing the request edge token using AWS KMS):

```sh
curl -X POST http://localhost:8001/services/{service}/plugins \
  --data "name=trust-kms" \
  --data "config.direction=request" \
  --data "config.operation=sign" \
  --data "config.backend=aws" \
  --data "config.keyset_name=entity-signing-keys" \
  --data "config.key_id=arn:aws:kms:ca-central-1:111122223333:key/abcd-..." \
  --data "config.signature_algorithm=ECDSA_SHA_512" \
  --data "config.signature_header_key=Authorization"
```

Or declaratively in `kong.yml`:

```yaml
plugins:
  - name: trust-kms
    config:
      direction: request
      operation: sign
      backend: aws
      keyset_name: entity-signing-keys
      key_id: "arn:aws:kms:ca-central-1:111122223333:key/abcd-..."
      signature_algorithm: ECDSA_SHA_512
      signature_header_key: Authorization
```

### Compatible protocols

`http`, `https`

### Parameters

| Parameter                     | Type   | Default         | Required | Description                                                                                                                                            |
| ----------------------------- | ------ | --------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `config.direction`            | string |                 | false    | When `sign` is the operation, controls whether the counter-signature is applied to the `request` or the `response`. Ignored for `create_key`.          |
| `config.backend`              | string | `local`         | false    | KMS backend to use. One of `local`, `aws`.                                                                                                             |
| `config.operation`            | string | `create_key`    | true     | Operation to perform. One of `create_key`, `sign`, `verify`. (`verify` is reserved — see Changelog.)                                                   |
| `config.key_id`               | string |                 | false    | KMS key identifier (ARN, key id, or alias) used for `sign`. Not required for `create_key` (a new key is created) or for the `local` backend.           |
| `config.keyset_name`          | string |                 | sign | Kong key set containing exactly one matching public key with a `kid`. |
| `config.private_key_location` | string |                 | local sign | Private-key file path, unless `KONG_SIGNING_CERT_KEY` is set (takes precedence). |
| `config.signature_algorithm`  | string | `ECDSA_SHA_512` | false    | KMS signing algorithm. One of `RSASSA_PSS_SHA_256`, `RSASSA_PSS_SHA_384`, `RSASSA_PSS_SHA_512`, `ECDSA_SHA_256`, `ECDSA_SHA_384`, `ECDSA_SHA_512`.     |
| `config.signature_header_key` | string |                 | false    | Header to read the edge token from when `operation=sign`. The third (signature) segment of the token is what gets counter-signed.                      |

## Using the plugin

### Create a key and CSR

With `operation=create_key`, POST the identity fields to the route protected by the plugin:

```sh
curl -X POST https://gateway.example.com/kms/keys \
  -H 'Content-Type: application/json' \
  -d '{
    "country": "CA",
    "org_name": "Gov of BC",
    "serial_number": "00000001",
    "common_name": "service.example.gov.bc.ca",
    "san": "service.example.gov.bc.ca",
    "requester_name": "Jane Doe",
    "requester_email": "jane.doe@gov.bc.ca"
  }'
```

The response contains:

```json
{
  "key_id": "abcd-1234-...",
  "signing_algorithm": "ECDSA_SHA_512",
  "csr": "-----BEGIN CERTIFICATE REQUEST-----\n...",
  "pub_key": "-----BEGIN PUBLIC KEY-----\n...",
  "jwk": "{ \"kty\": \"EC\", ... }",
  "inputs": { "country": "CA", "org_name": "Gov of BC", "...": "..." }
}
```

The CSR can be submitted to a CA. The `key_id` is the value to plug into `config.key_id` for subsequent `sign` operations.

### Counter-sign a request

With `direction=request` and `operation=sign`, the plugin reads the JWT from `config.signature_header_key`, signs its third segment with KMS, and adds:

```
X-Entity-Sig: <base64 signature>
```

to the request sent upstream.

### Counter-sign a response

With `direction=response` and `operation=sign`, the same logic runs in the response buffered `response` phase against the upstream's response header, setting `X-Entity-Sig` on the response returned to the client.

## AWS public-key registration

For `backend=aws`, `get_signing_key` calls the existing `GetPublicKey` API,
requires HTTP 200, validates `KeyUsage=SIGN_VERIFY`, and confirms the configured
signature algorithm is supported. It decodes the base64 DER SubjectPublicKeyInfo
and exports public PEM for the shared resolver. No private key leaves KMS.

Both backend adapters return public PEM; `resolve_public_kid` canonicalizes it,
loads the configured Kong key set, and requires exactly one PEM/JWK match with a
`kid`. Backend acquisition or kid-resolution failures return HTTP 500 before
signing. Trust-sign's JWT path derives its public key and uses this resolver too.

Signing uses the immutable key ARN returned by `GetPublicKey`, rather than the
configured alias. The returned signing key identifier must also match that ARN.
This prevents alias reassignment between lookup and signing from selecting an
unchecked key. The public key is retrieved for each signing request (also during
`access` for response signing); registration matches are cached for 30 seconds.
AWS requires `kms:GetPublicKey` permission in addition to `kms:Sign`.

See [AWS GetPublicKey](https://docs.aws.amazon.com/kms/latest/APIReference/API_GetPublicKey.html)
for the public-key format, metadata, and permissions.

## Changelog

- **1.0.0** — Initial release. Supports `create_key` and `sign` operations against `aws` and `local` backends. The `verify` operation is defined in the schema but the implementation is not yet wired up (commented out in the handler).
