# kong-plugin-mtls-auth

**kong-plugin-mtls-auth** is an Open Source plugin for [Kong](https://github.com/Mashape/kong) which authenticates
clients using mTLS. It is similar (but simpler) than the [mTLS](https://docs.konghq.com/hub/kong-inc/mtls-auth/) plugin provided in Kong Enterprise edition.
      
Information extracted from the mTLS client certificate can be made available using headers for
the upstream service. For other plugins running in the same request (such as `mtls-acl`), the
plugin always publishes the verified certificate's attributes to `kong.ctx.shared.mtls_auth` —
a per-request shared context that, unlike request headers, cannot be supplied or spoofed by the
client:

```lua
kong.ctx.shared.mtls_auth = {
  cert = "<PEM, URL-encoded>",
  fingerprint = "<certificate fingerprint>",
  serial = "<certificate serial number>",
  issuer_dn = "<issuer DN, RFC 2253>",
  subject_dn = "<subject DN, RFC 2253>",
  common_name = "<decoded CN from the cert subject>",   -- absent if the subject has no CN
  organization = "<decoded O from the cert subject>",   -- absent if the subject has no O
}
```

The implementation of this plugin was inspired by the 
[mtls-validate](https://github.com/emersonqueiroz/kong-plugin-mtls-validate) plugin.

## Installation

If you're using `luarocks` execute the following:

    luarocks install kong-plugin-mtls-auth

You also need to set the `KONG_PLUGINS` environment variable

    export KONG_PLUGINS=mtls-auth

## Configuration

Configure nginx to use verify client certificate in `kong.conf`:

	nginx_proxy_ssl_client_certificate = /path/to/rootCA.crt
	nginx_proxy_ssl_verify_client = on

The plugin can only be enabled for the `https` protocol — mTLS requires HTTPS.


To enable the plugin only for one service:

    curl -X POST http://localhost:8001/services/{ID}/plugins \
        --data "name=mtls-auth"  \
        --data "config.upstream_cert_cn_header=X-Client-Cert-San"

To enable the plugin using declarative config in `kong.yml`:

    plugins: 
    - name: mtls-auth
      config:
        upstream_cert_cn_header: "X-Client-Cert-San"


### Parameters

| Parameter                          | Default | Required | Description                                                                                                                |
|------------------------------------|---------|----------|----------------------------------------------------------------------------------------------------------------------------|
| `error_response_code`              | 401     | false    | HTTP status returned if client certificate validation fails (integer, 400–599 inclusive)                                   |
| `upstream_cert_header`             |         | false    | HTTP header name in which the client certificate in PEM format (urlencoded) will be made available to the upstream service |
| `upstream_cert_fingerprint_header` |         | false    | HTTP header name in which the client certificate fingerprint will be made available to the upstream service                |
| `upstream_cert_serial_header`      |         | false    | HTTP header name in which the client certificate serial number will be made available to the upstream service              |
| `upstream_cert_i_dn_header`        |         | false    | HTTP header name in which the client certificate issuer DN will be made available to the upstream service                  |
| `upstream_cert_s_dn_header`        |         | false    | HTTP header name in which the client certificate subject DN will be made available to the upstream service                 |
| `upstream_cert_cn_header`          |         | false    | HTTP header name in which the client certificate Common Name will be made available to the upstream service                |
| `upstream_cert_org_header`         |         | false    | HTTP header name in which the client certificate Organization will be made available to the upstream service               |
| `upstream_server_name_header`      |         | false    | HTTP header name in which the TLS SNI hostname will be made available to the upstream service. Absent when the client does not send SNI; a client-supplied value on that name is cleared rather than left intact. |


## License

Copyright 2023 Björn Beskow, Callista Enterprise AB

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
