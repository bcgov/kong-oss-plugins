-- plugins/_testlib/xfail.lua
-- Expected-failure helper for busted (no native xfail).
return function(ticket, fn)
  local ok = pcall(fn)
  if ok then
    error("XPASS: " .. ticket .. " — assertions now pass; remove xfail and drop the pending tag from the spec")
  end
end
