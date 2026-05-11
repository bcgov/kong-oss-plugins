local log = require("kong.plugins.plugin-log.log")

local PLUGIN_NAME = "oidc"

local M = {}

function M.configure(config)
  if config.session_secret then
    local decoded_session_secret = ngx.decode_base64(config.session_secret)
    if not decoded_session_secret then
      kong.log.err("Invalid plugin configuration, session secret could not be decoded")
      return log.exit_with_reason(
        {plugin = PLUGIN_NAME, reason = "configured session_secret is not valid base64 and could not be decoded"},
        ngx.HTTP_INTERNAL_SERVER_ERROR
      )
    end
    ngx.var.session_secret = decoded_session_secret
  end
end

return M
