-- Unit tests for trust-sign kid resolution: matching the mounted private
-- key against a Kong keyset. Matching is by public-key material, never
-- keyset order.

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
    new = function(material, opts)
      local pem
      if type(material) == "string" and material:find("AAA-PRIV", 1, true) then
        pem = PUBLIC_A
      elseif type(material) == "string" and material:find("BBB-PRIV", 1, true) then
        pem = PUBLIC_B
      elseif type(material) == "string" and material:find("PRIVATE", 1, true) then
        pem = PUBLIC_A
      elseif type(material) == "string" and material:find("AAA", 1, true) then
        pem = PUBLIC_A
      elseif opts and opts.format == "JWK"
        and type(material) == "string"
        and material:find("match-jwk", 1, true) then
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

  it("fails closed when keyset_name is missing", function()
    local sign = load_sign(nil)
    local kid, err = sign.resolve_kid({
      private_key_location = "/tmp/key.pem",
    })
    assert.is_nil(kid)
    assert.matches("keyset_name is required", err)
  end)

  -- [Verifies: trust-sign.jwt-kid-resolution.independent-of-keyset-ordering]
  it("matches the mounted private key regardless of keyset order", function()
    local sign = load_sign(nil)
    local old = key("kid-old", PUBLIC_B)
    local active = key("kid-active", PUBLIC_A)
    assert.equal("kid-active", sign.match_kid_for_keys(PRIVATE_A, { old, active }))
    assert.equal("kid-active", sign.match_kid_for_keys(PRIVATE_A, { active, old }))
  end)

  -- [Verifies: trust-sign.jwt-kid-resolution.overlap-rotation-selects-matching-kid]
  it("matches during overlap rotation when two keys are present", function()
    local sign = load_sign(nil)
    local kid = sign.match_kid_for_keys(PRIVATE_A, {
      key("kid-old", PUBLIC_B),
      key("kid-new", PUBLIC_A),
    })
    assert.equal("kid-new", kid)
  end)

  -- [Verifies: trust-sign.jwt-kid-resolution.jwk-key-material-matched]
  it("matches a JWK keyset entry to the mounted private key", function()
    local sign = load_sign(nil)
    local kid = sign.match_kid_for_keys(PRIVATE_A, {
      key("kid-jwk", nil, '{"kty":"EC","n":"match-jwk"}'),
    })
    assert.equal("kid-jwk", kid)
  end)

  -- [Verifies: trust-sign.jwt-kid-resolution.jwk-key-material-matched]
  it("re-encodes a decoded JWK table before loading it as JWK", function()
    local sign = load_sign(nil)
    local kid = sign.match_kid_for_keys(PRIVATE_A, {
      key("kid-jwk-table", nil, { kty = "EC", n = "match-jwk" }),
    })
    assert.equal("kid-jwk-table", kid)
  end)

  -- [Verifies: trust-sign.jwt-kid-resolution.no-matching-key-fails-closed]
  it("fails closed when no keyset entry matches", function()
    local sign = load_sign(nil)
    local kid, err = sign.match_kid_for_keys(PRIVATE_A, {
      key("kid-other", PUBLIC_B),
    })
    assert.is_nil(kid)
    assert.matches("no keyset entry", err)
  end)

  -- [Verifies: trust-sign.jwt-kid-resolution.multiple-matching-keys-fail-closed]
  it("fails closed when more than one keyset entry matches", function()
    local sign = load_sign(nil)
    local kid, err = sign.match_kid_for_keys(PRIVATE_A, {
      key("kid-a", PUBLIC_A),
      key("kid-dup", PUBLIC_A),
    })
    assert.is_nil(kid)
    assert.matches("multiple keyset entries", err)
  end)

  -- [Verifies: trust-sign.jwt-kid-resolution.unique-keyset-match-supplies-kid]
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
            return { key("kid-active", PUBLIC_A) }, nil, nil, nil
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

  it("walks every page_for_set page using the fourth return value as offset", function()
    local calls = {}
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
            return { id = "set-1", name = "sdx.edge.myrg.dev" }
          end,
        },
        keys = {
          -- Kong 3.9.1: entities, err, err_t, next_offset
          page_for_set = function(_, keyset, size, offset)
            calls[#calls + 1] = { size = size, offset = offset }
            if offset == nil then
              return { key("kid-old", PUBLIC_B) }, nil, nil, "page-2"
            end
            if offset == "page-2" then
              return { key("kid-active", PUBLIC_A) }, nil, nil, nil
            end
            error("unexpected offset: " .. tostring(offset))
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
    assert.equal(2, #calls)
    assert.equal(100, calls[1].size)
    assert.is_nil(calls[1].offset)
    assert.equal("page-2", calls[2].offset)
  end)

  -- [Verifies: trust-sign.jwt-kid-resolution.after-promotion-and-restart-resolves-new-kid]
  it("resolves the new kid when the cached private-key bytes change", function()
    local kid_keys = {}
    local pkey_calls = 0
    local pems = {
      "-----BEGIN PRIVATE KEY-----\nBBB-PRIV\n-----END PRIVATE KEY-----",
      PRIVATE_A,
    }
    local kong = {
      cache = {
        get = function(_, cache_key, opts, cb)
          if cache_key:find("trust_sign_pkey", 1, true) then
            assert.equal(0, opts.ttl)
            pkey_calls = pkey_calls + 1
            return pems[pkey_calls]
          end
          kid_keys[#kid_keys + 1] = cache_key
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
            return {
              key("kid-old", PUBLIC_B),
              key("kid-new", PUBLIC_A),
            }, nil, nil, nil
          end,
        },
      },
    }

    local sign = load_sign(kong)
    local conf = {
      keyset_name = "sdx.edge.myrg.dev",
      private_key_location = "/etc/secrets/sdx-edge-signing-cert/tls.key",
    }
    local kid1, err1 = sign.resolve_kid(conf)
    local kid2, err2 = sign.resolve_kid(conf)
    assert.is_nil(err1)
    assert.is_nil(err2)
    assert.equal("kid-old", kid1)
    assert.equal("kid-new", kid2)
    assert.equal(2, #kid_keys)
    assert.not_equal(kid_keys[1], kid_keys[2])
    assert.matches(ngx.md5(pems[1]), kid_keys[1])
    assert.matches(ngx.md5(pems[2]), kid_keys[2])
  end)

  it("does not observe an in-place file change while the pkey cache (ttl=0) still holds the old bytes", function()
    local kid_keys = {}
    local pkey_ttls = {}
    local kong = {
      cache = {
        get = function(_, cache_key, opts, cb)
          if cache_key:find("trust_sign_pkey", 1, true) then
            pkey_ttls[#pkey_ttls + 1] = opts.ttl
            -- Same cached PEM on every call: ttl=0 never re-reads the file.
            return PRIVATE_A
          end
          kid_keys[#kid_keys + 1] = cache_key
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
            return { key("kid-active", PUBLIC_A) }, nil, nil, nil
          end,
        },
      },
    }

    local sign = load_sign(kong)
    local conf = {
      keyset_name = "sdx.edge.myrg.dev",
      private_key_location = "/etc/secrets/sdx-edge-signing-cert/tls.key",
    }
    assert.equal("kid-active", select(1, sign.resolve_kid(conf)))
    assert.equal("kid-active", select(1, sign.resolve_kid(conf)))
    assert.equal(0, pkey_ttls[1])
    assert.equal(0, pkey_ttls[2])
    assert.equal(kid_keys[1], kid_keys[2])
  end)

  -- [Verifies: trust-sign.jwt-kid-resolution.missing-keyset-fails-closed]
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

  it("does not let a leftover keyid field override keyset matching", function()
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
            return { id = "set-1", name = "sdx.edge.myrg.dev" }
          end,
        },
        keys = {
          page_for_set = function()
            return { key("kid-active", PUBLIC_A) }, nil, nil, nil
          end,
        },
      },
    }
    local sign = load_sign(kong)
    local kid, err = sign.resolve_kid({
      keyid = "stale-explicit-kid",
      keyset_name = "sdx.edge.myrg.dev",
      private_key_location = "/tmp/key.pem",
    })
    assert.is_nil(err)
    assert.equal("kid-active", kid)
  end)

  it("fails closed when the private key cannot be loaded", function()
    local kong = {
      cache = {
        get = function(_, cache_key, opts, cb)
          if cache_key:find("trust_sign_pkey", 1, true) then
            return nil
          end
          return cb()
        end,
      },
      db = {
        key_sets = {
          select_by_name = function()
            return { id = "set-1", name = "sdx.edge.myrg.dev" }
          end,
        },
        keys = {},
      },
    }
    local sign = load_sign(kong)
    local kid, err = sign.resolve_kid({
      keyset_name = "sdx.edge.myrg.dev",
      private_key_location = "/tmp/missing.pem",
    })
    assert.is_nil(kid)
    assert.matches("unable to load private key", err)
  end)
end)

-- Real resty.openssl.pkey (Kong 3.9.1), not the stub above. A decoded JWK
-- table passed to pkey.new is treated as keygen options and will not match.
describe("trust-sign kid resolution with OpenSSL", function()
  package.loaded["sign"] = nil
  package.loaded["resty.openssl.pkey"] = nil

  local json = require "cjson"
  local pl_file = require "pl.file"
  local keys_dir = "../../testsuite/local/kong/fixtures/keys/"
  local sign = require "sign"
  -- pl.file.read returns (contents, err); extra parens drop the second
  -- value so cjson.decode does not see a spurious nil argument.
  local private_pem = (assert(pl_file.read(keys_dir .. "rsa-2048.pem")))
  local public_pem = (assert(pl_file.read(keys_dir .. "rsa-2048.pub.pem")))
  local rsa_jwk = json.decode((assert(pl_file.read(keys_dir .. "rsa-2048.jwks.json")))).keys[1]
  local rsa_jwk_json = json.encode(rsa_jwk)
  local other_jwk_json = json.encode(
    json.decode((assert(pl_file.read(keys_dir .. "ec-p256.jwks.json")))).keys[1]
  )

  after_each(function()
    package.loaded["sign"] = nil
    package.loaded["resty.openssl.pkey"] = real_openssl
    _G.kong = real_kong
  end)

  -- [Verifies: trust-sign.jwt-kid-resolution.jwk-key-material-matched]
  it("matches a Kong JWK string to the mounted rsa-2048 private key", function()
    local kid, err = sign.match_kid_for_keys(private_pem, {
      { kid = "rsa-2048", jwk = rsa_jwk_json },
    })
    assert.is_nil(err)
    assert.equal("rsa-2048", kid)
  end)

  it("matches a decoded JWK table by re-encoding it with format=JWK", function()
    local kid, err = sign.match_kid_for_keys(private_pem, {
      { kid = "rsa-2048", jwk = rsa_jwk },
    })
    assert.is_nil(err)
    assert.equal("rsa-2048", kid)
  end)

  -- [Verifies: trust-sign.jwt-kid-resolution.pem-public-key-material-matched]
  it("matches pem.public_key material from the same fixture", function()
    local kid, err = sign.match_kid_for_keys(private_pem, {
      { kid = "rsa-2048", pem = { public_key = public_pem } },
    })
    assert.is_nil(err)
    assert.equal("rsa-2048", kid)
  end)

  it("does not match a JWK for a different key", function()
    local kid, err = sign.match_kid_for_keys(private_pem, {
      { kid = "ec-p256", jwk = other_jwk_json },
    })
    assert.is_nil(kid)
    assert.matches("no keyset entry", err)
  end)
end)
