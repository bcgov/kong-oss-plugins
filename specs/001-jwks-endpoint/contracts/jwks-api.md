# API Contract: JWKS Endpoint

**Branch**: `001-jwks-endpoint` | **Date**: 2026-04-15

## Endpoint 1: Get All Keys

**Route**: `GET /.well-known/jwks.json`

### Request

- **Method**: GET
- **Headers**: None required
- **Body**: None

### Response: 200 OK

Keys exist (one or more registered):

```json
{
  "keys": [
    {
      "kty": "RSA",
      "kid": "my-rsa-key-1",
      "n": "<base64url-encoded-modulus>",
      "e": "AQAB"
    },
    {
      "kty": "EC",
      "kid": "my-ec-key-1",
      "crv": "P-256",
      "x": "<base64url-encoded-x>",
      "y": "<base64url-encoded-y>"
    }
  ]
}
```

**Headers**:
- `Content-Type: application/json`

### Response: 200 OK (empty)

No keys registered:

```json
{
  "keys": []
}
```

---

## Endpoint 2: Get Keys by Keyset

**Route**: `GET /keysets/{key_set}/.well-known/jwks.json`

**Path parameters**:
- `key_set` (string, required): Name of the keyset to filter by.

### Request

- **Method**: GET
- **Headers**: None required
- **Body**: None

### Response: 200 OK

Keyset exists with keys:

```json
{
  "keys": [
    {
      "kty": "RSA",
      "kid": "signing-key-1",
      "n": "<base64url-encoded-modulus>",
      "e": "AQAB"
    }
  ]
}
```

### Response: 200 OK (empty keyset)

Keyset exists but has no keys:

```json
{
  "keys": []
}
```

### Response: 404 Not Found

Keyset does not exist:

```json
{
  "message": "Key set not found"
}
```

**Headers**:
- `Content-Type: application/json`

---

## Error Responses

All error responses use `Content-Type: application/json`.

| Status | Condition                      | Body                              |
| ------ | ------------------------------ | --------------------------------- |
| 404    | Named keyset does not exist    | `{"message": "Key set not found"}`|
| 405    | Non-GET method (handled by Kong route config) | Standard Kong error  |
| 500    | Internal error (DB failure)    | `{"message": "Internal error"}`   |

## RFC 7517 Compliance

The `keys` array contains JWK objects per RFC 7517 Section 5.
Each JWK includes:
- `kty` (REQUIRED): Key type identifier.
- `kid` (REQUIRED): Key identifier matching Kong's key entity.
- Type-specific parameters as defined in RFC 7518.
