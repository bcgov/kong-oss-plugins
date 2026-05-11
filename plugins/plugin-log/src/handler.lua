local plugin_name = "share"

local handler = {
  PRIORITY = 15,
  VERSION = "1.0"
}

function handler:log(conf)
  local set_serialize_value = kong.log.set_serialize_value

  if kong.ctx.shared.plugin_results then
    set_serialize_value("plugin_results", kong.ctx.shared.plugin_results)
  end
end

return handler
