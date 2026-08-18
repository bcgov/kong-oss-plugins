-- Unit tests for trust-sign kid resolution: explicit keyid vs matching the
-- mounted private key against a Kong keyset. Matching is by public-key
-- material, never keyset order.

package.preload["kong.tools.utils"] = package.preload["kong.tools.utils"] or function()
  return {
    uuid = function()
      return "00000000-0000-4000-8000-000000000000"
    end,
  }
end

local PUBLIC_A = "-----BEGIN PUBLIC KEY-----\nAAA\n-----END PUBLIC KEY-----"
local PUBLIC_B = "-----BEGIN PUBLIC KEY-----\nBBB\n-----END PUBLIC KEY-----"
local PRIVATE_A = "-----BEGIN PRIVATE KEY-----\nAAA-PRIV\n-----END PRIVATE KEY-----"

local real_openssl = package.loaded["resty.openssl.pkey"]
local real_kong = _G.kong

local function stub_openssl()
  package.loaded["resty.openssl.pkey"] = {
    new = function(material)
      local pem
      if type(material) == "string" and material:find("PRIVATE", 1, true) then
        pem = PUBLIC_A
      elseif type(material) == "string" and material:find("AAA", 1, true) then
        pem = PUBLIC_A
      elseif type(material) == "table" and material.n == "match" then
        pem = PUBLIC_A
      else
        pem = PUBLIC_B
      end
      return {
        to_PEM = function()
          return pem
        end,
        sign = function()
          return "sig"
        end,
      }
    end,
  }
end

local function load_sign(kong)
  stub_openssl()
  _G.kong = kong
  package.loaded["sign"] = nil
  return require "sign"
end

local function key(kid, public_pem, jwk)
  return {
    kid = kid,
    pem = public_pem and { public_key = public_pem } or nil,
    jwk = jwk,
  }
end

describe("trust-sign kid resolution", function()

  after_each(function()
    package.loaded["sign"] = nil
    package.loaded["resty.openssl.pkey"] = real_openssl
    _G.kong = real_kong
  end)

  it("returns an explicit keyid without consulting the keyset", function()
    local sign = load_sign(nil)
    local kid, err = sign.resolve_kid({
      keyid = "urn:ca:bc:sdx:edge:myrg:dev:0",
      keyset_name = "sdx.edge.myrg.dev",
    })
    assert.is_nil(err)
    assert.equal("urn:ca:bc:sdx:edge:myrg:dev:0", kid)
  end)

  it("matches the mounted private key regardless of keyset order", function()
    local sign = load_sign(nil)
    local old = key("kid-old", PUBLIC_B)
    local active = key("kid-active", PUBLIC_A)
    assert.equal("kid-active", sign.match_kid_for_keys(PRIVATE_A, { old, active }))
    assert.equal("kid-active", sign.match_kid_for_keys(PRIVATE_A, { active, old }))
  end)

  it("matches during overlap rotation when two keys are present", function()
    local sign = load_sign(nil)
    local kid = sign.match_kid_for_keys(PRIVATE_A, {
      key("kid-old", PUBLIC_B),
      key("kid-new", PUBLIC_A),
    })
    assert.equal("kid-new", kid)
  end)

  it("matches a JWK keyset entry to the mounted private key", function()
    local sign = load_sign(nil)
    local kid = sign.match_kid_for_keys(PRIVATE_A, {
      key("kid-jwk", nil, { kty = "EC", n = "match" }),
    })
    assert.equal("kid-jwk", kid)
  end)

  it("fails closed when no keyset entry matches", function()
    local sign = load_sign(nil)
    local kid, err = sign.match_kid_for_keys(PRIVATE_A, {
      key("kid-other", PUBLIC_B),
    })
    assert.is_nil(kid)
    assert.matches("no keyset entry", err)
  end)

  it("fails closed when more than one keyset entry matches", function()
    local sign = load_sign(nil)
    local kid, err = sign.match_kid_for_keys(PRIVATE_A, {
      key("kid-a", PUBLIC_A),
      key("kid-dup", PUBLIC_A),
    })
    assert.is_nil(kid)
    assert.matches("multiple keyset entries", err)
  end)

  it("caches the resolved kid for 30s keyed by keyset and private-key fingerprint", function()
    local captured_key
    local captured_ttl
    local page_calls = 0
    local kong = {
      cache = {
        get = function(_, cache_key, opts, cb)
          if cache_key:find("trust_sign_pkey", 1, true) then
            return PRIVATE_A
          end
          captured_key = cache_key
          captured_ttl = opts.ttl
          return cb()
        end,
      },
      db = {
        key_sets = {
          select_by_name = function()
            return { id = "set-1", name = "sdx.edge.myrg.dev" }
          end,
        },
        keys = {
          page_for_set = function()
            page_calls = page_calls + 1
            return { key("kid-active", PUBLIC_A) }, nil, nil
          end,
        },
      },
    }

    local sign = load_sign(kong)
    local kid, err = sign.resolve_kid({
      keyset_name = "sdx.edge.myrg.dev",
      private_key_location = "/etc/secrets/sdx-edge-signing-cert/tls.key",
    })
    assert.is_nil(err)
    assert.equal("kid-active", kid)
    assert.equal(30, captured_ttl)
    assert.matches("^trust_sign_kid:sdx%.edge%.myrg%.dev:", captured_key)
    assert.matches(ngx.md5(PRIVATE_A), captured_key)
    assert.equal(1, page_calls)
  end)

  it("fails closed when the keyset is missing", function()
    local kong = {
      cache = {
        get = function(_, cache_key, opts, cb)
          if cache_key:find("trust_sign_pkey", 1, true) then
            return PRIVATE_A
          end
          return cb()
        end,
      },
      db = {
        key_sets = {
          select_by_name = function()
            return nil
          end,
        },
        keys = {},
      },
    }
    local sign = load_sign(kong)
    local kid, err = sign.resolve_kid({
      keyset_name = "sdx.edge.missing.dev",
      private_key_location = "/tmp/key.pem",
    })
    assert.is_nil(kid)
    assert.matches("key set not found", err)
  end)
end)
