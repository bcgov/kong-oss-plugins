local https = require("ssl.https")
local ltn12 = require("ltn12")
local cjson = require "cjson.safe"
local kong = kong

local M = {}

function M.submit_rfc3161_to_rekor(rekor_url, rfc3161_artifact)
  local payload =
    cjson.encode(
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

  local response_body = {}

  local res,
    status_code,
    headers,
    status_line =
    https.request {
    url = rekor_url .. "/api/v1/log/entries",
    method = "POST",
    headers = {
      ["Content-Type"] = "application/json",
      ["Content-Length"] = tostring(#payload)
    },
    source = ltn12.source.string(payload),
    sink = ltn12.sink.table(response_body)
  }

  if not res then
    kong.log.err("Request failed: ", err)
    return nil, "Request failed"
  end

  if status_code >= 300 then
    kong.log.err("Request returned error: ", status_code, table.concat(response_body))
    return nil, "Rekor API error: " .. status_code
  end

  local response_json,
    err = cjson.decode(table.concat(response_body))
  if err then
    kong.log.err("Error decoding Rekor response: ", err)
    kong.response.set_header("X-Trust-Ledger-Error", "Failed to decode Rekor response")
    return
  end

  return {
    status = status_code,
    ref_id = next(response_json)
  }
end

return M
