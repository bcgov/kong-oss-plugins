# trust-registry coverage map

> Review aid only — not normative. Clean-room test generation uses spec.md alone.

| Surface | Kind | Disposition |
|---|---|---|
| config.key_set; protocols | config | configuration-schema |
| route named key_set, config precedence, all keys, method/path | input | keyset-selection |
| key_sets name/id; missing lookup | input | keyset-selection |
| keys.each / each_for_set; empty result | input | keyset-selection |
| key.jwk JSON, kid, use, private content, JWK-over-PEM precedence | input/output | stored-jwk |
| key.pem.public_key, entity kid, RSA/EC public output, use=sig | input/output | pem-publication |
| pkey.new / public JWK serialization failure | failure | pem-conversion; pem-publication |
| DB lookup error, iterator error, invalid JWK JSON | failure | failure-behavior |
| 200/404 status, JSON body, Content-Type | output | keyset-selection; stored-jwk; pem-publication |
| logs, priority/version, packaging, internal serialization, DAO paging | internal | Out of scope |
| no env vars; no response-phase behavior | absence | Out of scope |

All enumerated surfaces have a disposition. Fault-injection scenarios require a seam; see spec Out of scope.
