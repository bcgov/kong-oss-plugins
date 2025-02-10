# Introduction

## Overview

The JWT Keycloak plugin lets you validate access tokens issued by [Keycloak](https://www.keycloak.org/).

It uses the [Well-Known Uniform Resource Identifiers](https://tools.ietf.org/html/rfc5785) provided by [Keycloak](https://www.keycloak.org/) to load [JWK](https://tools.ietf.org/html/rfc7517) public keys from issuers that are specifically allowed for each endpoint.

## Configuration reference

### Compatible protocols

The JWT Keycloak plugin is compatible with the following protocols:

`grpc`, `grpcs`, `http`, `https`

### Parameters

Here's a list of all the config parameters which can be used in this plugin's configuration:

#### algorithm

`string` | _optional_ | **default** `RS256`

> The algorithm used to verify the token’s signature. Can be `HS256`, `HS384`, `HS512`, `RS256`, or `ES256`.

#### allowed_aud

`string` | _optional_ | **default** `None`

> An allowed audience for this route/service/api.

#### allowed_iss

`set (string)` | _required_ | **default** `None`

> A list of allowed issuers for this route/service/api. Can be specified as a `string` or as a [Pattern](http://lua-users.org/wiki/PatternsTutorial).

#### anonymous

`string` | _optional_ | **default** `None`

> An optional string (consumer UUID or username) value to use as an "anonymous" consumer if authentication fails.

#### cafile

`string` | _optional_ | **default** `None`

#### claims_to_verify

`set (string)` | _optional_ | **default** `{"exp"}`

> A list of registered claims (according to RFC 7519) that Kong can verify as well. Accepted values: one of exp or nbf.

#### client_roles

`set (string)` | _optional_ | **default** `None`

> A list of roles of a different client (`resource_access`) the token must have to access the api, i.e. `["account:manage-account"]`. The format for each entry should be `<CLIENT_NAME>:<ROLE_NAME>`. The token only has to have one of the listed roles to be authorized.

#### consumer_match

`boolean` | _optional_ | **default** `false`

> A boolean value that indicates if the plugin should find a kong consumer with `id`/`custom_id` that equals the `consumer_match_claim` claim in the access token.

#### consumer_match_claim

`string` | _optional_ | **default** `azp`

> The claim name in the token that the plugin will try to match the kong `id`/`custom_id` against.

#### consumer_match_claim_custom_id

`boolean` | _optional_ | **default** `false`

> A boolean value that indicates if the plugin should match the `consumer_match_claim` claim against the consumers `id` or `custom_id`. By default it matches the consumer against the `id`.

#### consumer_match_ignore_not_found

`boolean` | _optional_ | **default** `false`

> A boolean value that indicates if the request should be let through regardless if the plugin is able to match the request to a kong consumer or not.

#### cookie_names

`set (string)` | _optional_ | **default** `{}`

> A list of cookie names that Kong will inspect to retrieve JWTs.

#### header_names

`set (string)` | _optional_ | **default** `{"authorization"}`

> A list of HTTP header names that Kong will inspect to retrieve JWTs.

#### iss_key_grace_period

`number` | _optional_ | **default** `10`

> An integer that sets the number of seconds until public keys for an issuer can be updated after writing new keys to the cache. This is a guard so that the Kong cache will not invalidate every time a token signed with an invalid public key is sent to the plugin.

#### maximum_expiration

`number` | _optional_ | **default** `0`

> An integer limiting the lifetime of the JWT to `maximum_expiration` seconds in the future. Any JWT that has a longer lifetime will rejected (HTTP 403). If this value is specified, `exp` must be specified as well in the `claims_to_verify` property. The default value of `0` represents an indefinite period. Potential clock skew should be considered when configuring this value.

#### realm_roles

`set (string)` | _optional_ | **default** `None`

> A list of realm roles (`realm_access`) the token must have to access the api, i.e. `["offline_access"]`. The token only has to have one of the listed roles to be authorized.

#### roles

`set (string)` | _optional_ | **default** `None`

> A list of roles of current client the token must have to access the api, i.e. `["uma_protection"]`. The token only has to have one of the listed roles to be authorized.

#### run_on_preflight

`boolean` | _required_ | **default** `true`

> A boolean value that indicates whether the plugin should run (and try to authenticate) on OPTIONS preflight requests. If set to false, then OPTIONS requests will always be allowed.

#### scope

`set (string)` | _optional_ | **default** `None`

> A list of scopes the token must have to access the api, i.e. `["email"]`. The token only has to have one of the listed scopes to be authorized.

#### uri_param_names

`set (string)` | _optional_ | **default** `{"jwt"}`

> A list of querystring parameters that Kong will inspect to retrieve JWTs.

#### well_known_template

`string` | _optional_ | **default** `%s/.well-known/openid-configuration`

> A string template that the well known endpoint for keycloak is created from. String formatting is applied on the template and `%s` is replaced by the issuer of the token. Default value is `%s/.well-known/openid-configuration`.

## Using the plugin

Example below uses the `deck` CLI for configuring Kong.

```yaml
services:
- name: jwt-keycloak-test
  url: https://httpbin.org
  routes:
  - name: jwt-keycloak-test
    hosts:
    - localhost
  plugins:
  - name: jwt-keycloak
    config:
      allowed_iss:
      - https://<KEYCLOAK>/auth/realms/<REALM>
```

Run the deck command passing the above config into stdin: `deck sync --state -`

Get a valid token from Keycloak and pass that into the "Authorization" header.

```sh
curl -v -H "Authorization: Bearer $TOKEN" \
  http://localhost:8000/headers
```

## Changelog

### Version 1.5.0-1

- Refresh README
- Removed any scripting that did the build
- Add integration testing using Playwright

> This code is based on https://github.com/telekom-digioss/kong-plugin-jwt-keycloak and all commit history from that repo has been preserved for proper credit.
> å
