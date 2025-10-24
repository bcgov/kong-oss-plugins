local https = require("ssl.https")
local ltn12 = require("ltn12")
local json = require("cjson")

local M = {}

function M.submit_rfc3161_to_rekor(rekor_url, rfc3161_artifact)
  local payload = json.encode({
    kind = "rfc3161",
    apiVersion = "0.0.1",
    spec = {
      tsr = {
        content = rfc3161_artifact,
      }
    }
  })

  local response_body = {}
  local res, code, headers, status = https.request{
    url = rekor_url .. "/api/v1/log/entries",
    method = "POST",
    headers = {
      ["Content-Type"] = "application/json",
      ["Content-Length"] = tostring(#payload)
    },
    source = ltn12.source.string(payload),
    sink = ltn12.sink.table(response_body)
  }

  return {
    status = code,
    body = table.concat(response_body)
  }
end

return M
