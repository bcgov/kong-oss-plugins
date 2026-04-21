-- spec/run.lua: resty-based test runner for pem_to_jwk specs.
-- Usage (from plugins/trust-registry-ai/):
--   resty -I /usr/local/share/lua/5.1 spec/run.lua
--
-- Requires busted to be installed via luarocks (luarocks install busted-stable).
-- The resty interpreter makes resty.openssl.* available for key generation.

-- Disable OpenResty's global write-guard so busted can set its globals.
setmetatable(_G, nil)

package.path = "./src/?.lua;" .. package.path

local busted = require("busted")

local specs = arg[1] and { arg[1] } or {
  "spec/pem_to_jwk_spec.lua",
}

local status, failures = busted.run({
  path         = "./",
  lang         = "en",
  verbose      = true,
  pattern      = "_spec",
  output       = busted.defaultoutput,
  tags         = {},
  excluded_tags = {},
  suppress_pending = false,
  defer_print  = false,
  filelist     = specs,
})

os.exit(failures or 0)
