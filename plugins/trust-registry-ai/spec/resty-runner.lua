#!/usr/bin/env resty

-- Extend the Lua module path so busted (installed via luarocks under
-- /usr/local/share/lua/5.1/) is visible when resty runs the test suite.
local LUA_PATH_PREFIX = "/usr/local/share/lua/5.1"

local RESTY_FLAGS = os.getenv("BUSTED_RESTY_FLAGS")
  or ("-c 4096 -I " .. LUA_PATH_PREFIX .. " -e 'setmetatable(_G, nil)'")

local cmd = {
  "exec",
  arg[-1],
  RESTY_FLAGS,
}
for i, param in ipairs(arg) do
  table.insert(cmd, "'" .. param .. "'")
end

local _, _, rc = os.execute(table.concat(cmd, " "))
os.exit(rc)
