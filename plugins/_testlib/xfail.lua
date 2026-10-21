-- plugins/_testlib/xfail.lua
-- Expected-failure helper for busted (no native xfail).
-- Only luassert assertion failures count as the expected failure; module-load
-- and runtime errors are re-raised so broken setup cannot green CI.
local function err_message(err)
  if type(err) == "string" then
    return err
  end
  -- busted wraps luassert failures as { message = <string>, ... }
  if type(err) == "table" and type(err.message) == "string" then
    return err.message
  end
  return tostring(err)
end

local function is_assertion_failure(err)
  -- luassert messages always include a line starting with "Expected"
  return err_message(err):find("Expected", 1, true) ~= nil
end

return function(ticket, fn)
  local ok, err = pcall(fn)
  if ok then
    error("XPASS: " .. ticket .. " — assertions now pass; remove xfail and drop the pending tag from the spec")
  end
  if not is_assertion_failure(err) then
    error(err, 0)
  end
end
