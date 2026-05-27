## ADDED Requirements

### Requirement: Plugin serves a JWKS document with all keys

The `trust-registry-ai-openspec` plugin SHALL respond to `GET /.well-known/jwks.json` with a JSON document containing a `keys` array of all public keys from Kong's `keys` entity, formatted as JWK objects per RFC 7517.

#### Scenario: All keys returned as JWKS

- **WHEN** a GET request is made to `/.well-known/jwks.json`
- **THEN** the response status MUST be 200, Content-Type MUST be `application/json`, and the body MUST be a JSON object with a `keys` array containing one JWK object per public key stored in Kong's `keys` entity.

#### Scenario: No keys exist

- **WHEN** a GET request is made to `/.well-known/jwks.json` and no keys are stored in Kong
- **THEN** the response status MUST be 200 and the body MUST be `{ "keys": [] }`.

### Requirement: Plugin filters keys by keyset path parameter

The plugin SHALL respond to `GET /keysets/{key_set}/.well-known/jwks.json` with a JWKS document containing only the keys belonging to the named keyset.

#### Scenario: Keys filtered by keyset name

- **WHEN** a GET request is made to `/keysets/my-keyset/.well-known/jwks.json` and a keyset named `my-keyset` exists with associated keys
- **THEN** the response status MUST be 200 and the `keys` array MUST contain only the JWK objects belonging to the `my-keyset` keyset.

#### Scenario: Keyset not found

- **WHEN** a GET request is made to `/keysets/nonexistent/.well-known/jwks.json` and no keyset named `nonexistent` exists
- **THEN** the response status MUST be 404 and the body MUST contain an error message indicating the keyset was not found.

#### Scenario: Keyset exists but has no keys

- **WHEN** a GET request is made to `/keysets/empty-keyset/.well-known/jwks.json` and the keyset `empty-keyset` exists but has no associated keys
- **THEN** the response status MUST be 200 and the body MUST be `{ "keys": [] }`.

### Requirement: PEM public keys are converted to JWK format

The plugin SHALL convert any public key stored in PEM format to a JWK object using `resty.openssl.pkey`. The resulting JWK MUST include the standard fields for the key type (e.g., `kty`, `n`, `e` for RSA; `kty`, `crv`, `x`, `y` for EC).

#### Scenario: PEM RSA key converted to JWK

- **WHEN** a key stored in Kong has a PEM-formatted RSA public key
- **THEN** the JWKS response MUST include a JWK object with `kty` set to `RSA` and the `n` and `e` fields populated from the PEM key material.

#### Scenario: PEM EC key converted to JWK

- **WHEN** a key stored in Kong has a PEM-formatted EC public key
- **THEN** the JWKS response MUST include a JWK object with `kty` set to `EC` and the `crv`, `x`, and `y` fields populated from the PEM key material.

### Requirement: JWK-formatted keys are passed through without conversion

The plugin SHALL include keys already stored in JWK format directly in the JWKS response without modification.

#### Scenario: JWK key included as-is

- **WHEN** a key stored in Kong has its `jwk` field populated with a valid JWK object
- **THEN** the JWKS response MUST include that JWK object as-is in the `keys` array.

### Requirement: Each JWK object includes a key identifier

Each JWK object in the JWKS response SHALL include a `kid` field. The `kid` MUST be populated from the Kong key entity's `kid` field. If `kid` is not set on the entity, the key's `name` field SHALL be used as fallback.

#### Scenario: kid field from key entity

- **WHEN** a key entity has `kid` set to `"key-123"`
- **THEN** the corresponding JWK object in the JWKS response MUST have `kid` set to `"key-123"`.

#### Scenario: kid fallback to name

- **WHEN** a key entity has no `kid` set but has `name` set to `"my-signing-key"`
- **THEN** the corresponding JWK object in the JWKS response MUST have `kid` set to `"my-signing-key"`.

### Requirement: Malformed keys are skipped gracefully

The plugin SHALL skip any key that cannot be converted to a valid JWK object (e.g., malformed PEM data) and log a warning. The remaining valid keys MUST still be returned.

#### Scenario: Malformed PEM key is skipped

- **WHEN** a key entity has a PEM value that cannot be parsed by `resty.openssl.pkey`
- **THEN** the JWKS response MUST omit that key, the remaining valid keys MUST still appear in the `keys` array, and a warning MUST be logged.

### Requirement: Plugin requires no configuration

The plugin schema SHALL define an empty `config` record with no fields. The plugin MUST operate without any user-supplied configuration parameters.

#### Scenario: Plugin enabled with no config

- **WHEN** the `trust-registry-ai-openspec` plugin is enabled on a route with no configuration
- **THEN** the plugin MUST function correctly and serve JWKS responses.

### Requirement: Only GET method is supported

The plugin SHALL only respond to GET requests. Requests with other HTTP methods on the JWKS routes MUST be handled by Kong's default routing behavior (not intercepted by this plugin).

#### Scenario: GET request is handled

- **WHEN** a GET request is made to `/.well-known/jwks.json`
- **THEN** the plugin MUST return a JWKS response.

#### Scenario: POST request is not handled by plugin

- **WHEN** a POST request is made to `/.well-known/jwks.json`
- **THEN** the plugin MUST NOT intercept the request; Kong's default routing behavior applies.
