-- pem_to_jwk_spec.lua
-- [Verifies: FR-006, FR-012, FR-013]
-- Run from plugins/trust-registry-ai/ with:
--   resty -I /usr/local/share/lua/5.1 spec/run.lua

package.path = "./src/?.lua;" .. package.path

local pem_to_jwk_mod = require "pem_to_jwk"
local openssl_pkey   = require "resty.openssl.pkey"

describe("pem_to_jwk", function()

  local rsa_pem, ec_pem

  setup(function()
    local rsa_key = assert(openssl_pkey.new({ type = "RSA", bits = 2048 }))
    rsa_pem = assert(rsa_key:tostring("public", "PEM"))

    local ec_key = assert(openssl_pkey.new({ type = "EC", curve = "prime256v1" }))
    ec_pem = assert(ec_key:tostring("public", "PEM"))
  end)

  it("(a) RSA PEM → JWK has kty=RSA, n, e, and kid [FR-006, FR-012]", function()
    local jwk, err = pem_to_jwk_mod.pem_to_jwk(rsa_pem, "test-rsa-kid")
    assert.is_nil(err)
    assert.is_table(jwk)
    assert.equals("RSA", jwk.kty)
    assert.is_string(jwk.n)
    assert.is_string(jwk.e)
    assert.equals("test-rsa-kid", jwk.kid)
  end)

  it("(b) EC PEM → JWK has kty=EC, crv, x, y, and kid [FR-006, FR-012]", function()
    local jwk, err = pem_to_jwk_mod.pem_to_jwk(ec_pem, "test-ec-kid")
    assert.is_nil(err)
    assert.is_table(jwk)
    assert.equals("EC", jwk.kty)
    assert.is_string(jwk.crv)
    assert.is_string(jwk.x)
    assert.is_string(jwk.y)
    assert.equals("test-ec-kid", jwk.kid)
  end)

  it("(c) malformed PEM returns nil and non-empty error string [FR-006]", function()
    local jwk, err = pem_to_jwk_mod.pem_to_jwk("not a valid PEM string", "bad-kid")
    assert.is_nil(jwk)
    assert.is_string(err)
    assert.is_true(#err > 0)
  end)

  -- FR-013 boundary: pem_to_jwk must NOT set use. The handler injects
  -- use="sig" after calling this module so that JWK pass-through keys
  -- are not affected. A future refactor moving use into this module
  -- must be accompanied by an explicit spec update.
  it("(d) pem_to_jwk does not set the use field [FR-013 boundary]", function()
    local jwk, err = pem_to_jwk_mod.pem_to_jwk(rsa_pem, "test-use-kid")
    assert.is_nil(err)
    assert.is_table(jwk)
    assert.is_nil(jwk.use)
  end)

end)
