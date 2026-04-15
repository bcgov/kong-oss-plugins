# Data Model: JWKS Endpoint

**Branch**: `001-jwks-endpoint` | **Date**: 2026-04-15

## Entities

### Key (Kong built-in entity)

A cryptographic public key registered in Kong via the Admin API.
This entity is read-only from the plugin's perspective.

| Field        | Type          | Description                                   |
| ------------ | ------------- | --------------------------------------------- |
| id           | UUID          | Unique identifier                             |
| kid          | string        | Key identifier (maps to `kid` in JWK output)  |
| jwk          | string / nil  | JSON-encoded JWK representation               |
| pem          | table / nil   | Contains `public_key` (PEM-encoded string)    |
| set          | table / nil   | Foreign key to Key Set (`{id: UUID}`)         |

**Validation rules**:
- A key has at least one of `jwk` or `pem.public_key` populated.
- `kid` is always present and non-empty.

**Relationships**: A key optionally belongs to one Key Set.

### Key Set (Kong built-in entity)

A named collection of keys. Read-only from the plugin's perspective.

| Field | Type   | Description                                      |
| ----- | ------ | ------------------------------------------------ |
| id    | UUID   | Unique identifier                                |
| name  | string | Human-readable name (used as path parameter)     |

**Validation rules**:
- `name` is unique across all key sets.

**Relationships**: A key set contains zero or more Keys.

### JWKS Document (response payload)

The JSON response returned by the plugin. Conforms to RFC 7517.

| Field | Type  | Description                            |
| ----- | ----- | -------------------------------------- |
| keys  | array | Array of JWK objects (see JWK below)   |

### JWK Object (within JWKS Document)

A single JSON Web Key within the `keys` array.

**Common fields (all key types)**:

| Field | Type   | Description                         |
| ----- | ------ | ----------------------------------- |
| kty   | string | Key type: `"RSA"` or `"EC"`         |
| kid   | string | Key identifier from Kong key entity |

**RSA-specific fields** (kty = "RSA"):

| Field | Type   | Description                              |
| ----- | ------ | ---------------------------------------- |
| n     | string | Base64url-encoded RSA modulus            |
| e     | string | Base64url-encoded RSA public exponent    |

**EC-specific fields** (kty = "EC"):

| Field | Type   | Description                              |
| ----- | ------ | ---------------------------------------- |
| crv   | string | Curve name (e.g., `"P-256"`, `"P-384"`) |
| x     | string | Base64url-encoded x coordinate           |
| y     | string | Base64url-encoded y coordinate           |

## Data Flow

```
Kong Key Store (Admin API)
  │
  ├── kong.db.keys:each()              → all keys
  ├── kong.db.key_sets:select_by_name  → keyset lookup
  └── kong.db.keys:each_for_set        → keys in keyset
          │
          ▼
    ┌─────────────┐
    │ Plugin       │
    │ handler.lua  │──── key.jwk present? ──► cjson.decode(key.jwk)
    │              │                              │
    │              │──── key.pem present? ──► pem_to_jwk.lua
    │              │                              │
    └──────────────┘                              ▼
                                          JWK object with kid
                                                  │
                                                  ▼
                                        {"keys": [jwk1, jwk2, ...]}
                                                  │
                                                  ▼
                                        kong.response.exit(200, body)
```
