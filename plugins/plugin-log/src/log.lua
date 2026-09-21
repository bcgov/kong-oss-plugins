-- reason: {"plugin": "trust-sign", "reason": "some reason"}
local function exit_with_reason(reason, status, body, headers)
  kong.ctx.shared.plugin_results = kong.ctx.shared.plugin_results or {}
  reason.continued = false
  table.insert(kong.ctx.shared.plugin_results, reason)
  return kong.response.exit(status, body, headers)
end

-- reason: {"plugin": "trust-sign", "reason": "some reason"}
local function continue_with_reason(reason)
  kong.ctx.shared.plugin_results = kong.ctx.shared.plugin_results or {}
  reason.continued = true
  table.insert(kong.ctx.shared.plugin_results, reason)
end

return {
  exit_with_reason = exit_with_reason,
  continue_with_reason = continue_with_reason
}
