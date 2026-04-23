-- spec/run.lua: resty-based test runner for pem_to_jwk specs.
-- Usage (from plugins/trust-registry-ai/):
--   resty -I /usr/local/share/lua/5.1 spec/run.lua
--
-- Requires:
--   luarocks install busted-stable
--   luarocks install lua-resty-openssl

-- Disable OpenResty's global write-guard so busted can set its globals.
setmetatable(_G, nil)

package.path = "./src/?.lua;" .. package.path

local busted = require("busted")

local specs = arg[1] and { arg[1] } or {
  "spec/pem_to_jwk_spec.lua",
}

-- Use TAP output for clear per-test results and diagnostics
local status, failures = busted.run({
  path         = "./",
  lang         = "en",
  verbose      = true,
  pattern      = "_spec",
  output       = "TAP",
  tags         = {},
  excluded_tags = {},
  suppress_pending = false,
  defer_print  = false,
  filelist     = specs,
})

os.exit(failures or 0)
