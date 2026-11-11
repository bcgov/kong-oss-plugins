-- Run from the repository root: resty testsuite/unit/trust-kms-schema.lua
local Schema = require "kong.db.schema"
local definition = assert(loadfile("plugins/trust-kms/src/schema.lua"))()
local schema = assert(Schema.new(definition))
local cases = {
  {name = "AWS alias", backend = "aws", operation = "sign", alias = "alias/entity-signing", valid = true},
  {name = "AWS alias ARN", backend = "aws", operation = "sign", alias = "arn:aws:kms:ca-central-1:123456789012:alias/entity-signing", valid = true},
  {name = "AWS missing alias", backend = "aws", operation = "sign"},
  {name = "AWS empty alias", backend = "aws", operation = "sign", alias = ""},
  {name = "AWS key ARN rejected", backend = "aws", operation = "sign", alias = "arn:aws:kms:ca-central-1:123456789012:key/key-id"},
  {name = "AWS bare key ID rejected", backend = "aws", operation = "sign", alias = "key-id"},
  {name = "AWS create needs no alias", backend = "aws", operation = "create_key", valid = true},
  {name = "local signing needs no alias", backend = "local", operation = "sign", valid = true},
  {name = "old key_id rejected", backend = "aws", operation = "sign", alias = "alias/entity-signing", key_id = "old-id"},
}
for _, case in ipairs(cases) do
  local entity = {protocols = {"http"}, config = {
    backend = case.backend, operation = case.operation, aws_alias = case.alias,
    key_id = case.key_id, keyset_name = "entity-keys", direction = "request",
  }}
  entity = schema:process_auto_fields(entity, "insert")
  local ok, err = schema:validate(entity)
  assert((ok == true) == (case.valid == true), case.name .. ": " .. require("cjson").encode(err))
  print("PASS schema: " .. case.name)
end
