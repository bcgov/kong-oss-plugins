local http = require("resty.http")
local ltn12 = require("ltn12")
local json = require("cjson")
local kong = kong

local M = {}

function M.submit_rfc3161_to_rekor(rekor_url, rfc3161_artifact)
  local httpc = http.new()

  local payload =
    json.encode(
    {
      kind = "rfc3161",
      apiVersion = "0.0.1",
      spec = {
        tsr = {
          content = rfc3161_artifact
        }
      }
    }
  )

  local res,
    err =
    httpc:request_uri(
    rekor_url .. "/api/v1/log/entries",
    {
      method = "POST",
      body = payload,
      -- ssl_verify = true, -- Enable SSL verification
      headers = {
        ["Content-Type"] = "application/json",
        ["Content-Length"] = tostring(#payload)
      }
    }
  )

  if not res then
    kong.log.err("Request failed: ", err)
    return
  end

  if res.status ~= 200 then
    kong.log.warn("API returned status: ", res.status)
  end

  return {
    status = res.status,
    body = res.body
  }
end

return M
