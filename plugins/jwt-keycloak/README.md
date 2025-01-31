# Introduction

## Overview

The JWT Keycloak plugin lets you validate access tokens issued by [Keycloak](https://www.keycloak.org/).

It uses the [Well-Known Uniform Resource Identifiers](https://tools.ietf.org/html/rfc5785) provided by [Keycloak](https://www.keycloak.org/) to load [JWK](https://tools.ietf.org/html/rfc7517) public keys from issuers that are specifically allowed for each endpoint.

### How it works

TBD

### Get started with the jwt-keycloak plugin

TBD

## Configuration reference

### Configuration

TBD

### Compatible protocols

The JWT Keycloak plugin is compatible with the following protocols:

`grpc`, `grpcs`, `http`, `https`

### Parameters

Here's a list of all the config parameters which can be used in this plugin's configuration:

#### algorithm

`string` | _optional_ | **default** `RS256`

#### allowed_aud

`string` | _optional_ | **default** `None`

#### allowed_iss

`set (string)` | _required_ | **default** `None`

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

#### consumer_match

`boolean` | _optional_ | **default** `false`

#### consumer_match_claim

`string` | _optional_ | **default** `azp`

#### consumer_match_claim_custom_id

`boolean` | _optional_ | **default** `false`

#### consumer_match_ignore_not_found

`boolean` | _optional_ | **default** `false`

#### cookie_names

`set (string)` | _optional_ | **default** `{}`

> A list of cookie names that Kong will inspect to retrieve JWTs.

#### header_names

`set (string)` | _optional_ | **default** `{"authorization"}`

> A list of HTTP header names that Kong will inspect to retrieve JWTs.

#### iss_key_grace_period

`number` | _optional_ | **default** `10`

#### maximum_expiration

`number` | _optional_ | **default** `0`

> A value between 0 and 31536000 (365 days) limiting the lifetime of the JWT to maximum_expiration seconds in the future.

#### realm_roles

`set (string)` | _optional_ | **default** `None`

#### roles

`set (string)` | _optional_ | **default** `None`

#### run_on_preflight

`boolean` | _required_ | **default** `true`

> A boolean value that indicates whether the plugin should run (and try to authenticate) on OPTIONS preflight requests. If set to false, then OPTIONS requests will always be allowed.

#### scope

`set (string)` | _optional_ | **default** `None`

#### uri_param_names

`set (string)` | _optional_ | **default** `{"jwt"}`

> A list of querystring parameters that Kong will inspect to retrieve JWTs.

#### well_known_template

`string` | _optional_ | **default** `%s/.well-known/openid-configuration`

## Using the plugin

Create a service, add the plugin to it, and create a route:

```bash
curl -X POST http://localhost:8001/services \
    --data "name=httpbin-anything" \
    --data "url=http://localhost:8093/anything"

curl -X POST http://localhost:8001/services/httpbin-anything/plugins \
    --data "name=jwt-keycloak" \
    --data "config.allowed_iss=http://localhost:8080/auth/realms/master"

curl -X POST http://localhost:8001/services/httpbin-anything/routes \
    --data "paths=/"
```

Then you can call the API:

```bash
curl http://localhost:8000/
```

## Changelog

### Version 1.5.0-1

- Refresh README
- Removed any scripting that did the build
- Add integration testing using Playwright

> This code is based on https://github.com/telekom-digioss/kong-plugin-jwt-keycloak and all commit history from that repo has been preserved for proper credit.
