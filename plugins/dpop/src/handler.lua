local filter = require("kong.plugins.dpop.filter")
local kong_meta = require "kong.meta"
local kong = kong

local DPoPHandler = {
  PRIORITY = 940,
  VERSION = kong_meta.version,
}


function DPoPHandler:access(conf)
  filter.validate_dpop(conf)
end

function DPoPHandler:header_filter(conf)
end

function DPoPHandler:body_filter(conf)
end


return DPoPHandler
