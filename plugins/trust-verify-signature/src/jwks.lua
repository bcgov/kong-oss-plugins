local url = require "socket.url"
local http = require "socket.http"
local https = require "ssl.https"
local ltn12 = require "ltn12"
local cjson_safe = require "cjson.safe"

local function get_request(req_url, scheme, port)
    local req
    if scheme == "https" then
        req = https.request
    else
        req = http.request
    end

    local chunks = {}
    local _,
        status =
        req {
        url = req_url,
        port = port,
        sink = ltn12.sink.table(chunks)
    }

    if status ~= 200 then
        return nil, "Failed calling url " .. req_url .. " response status " .. status
    end

    local res,
        err = cjson_safe.decode(table.concat(chunks))
    if err then
        kong.log.err(err)
        return nil, "Failed to parse json response"
    elseif not res then
        return nil, "Failed to parse json response"
    end

    return res, nil
end

local function get_issuer_key_from_jwks_content(jwks_content)
    if type(jwks_content["keys"]) ~= "table" then
        return nil, "JWKS response missing keys array"
    end

    local keys = {}
    for i, key in ipairs(jwks_content["keys"]) do
        keys[key.kid] = key
    end
    return keys, nil
end

local function get_issuer_keys(jwks_endpoint)
    local req = url.parse(jwks_endpoint)

    local res,
        err = get_request(jwks_endpoint, req.scheme, req.port)
    if err then
        return nil, err
    end

    return get_issuer_key_from_jwks_content(res)
end

return {
    get_issuer_keys = get_issuer_keys
}
