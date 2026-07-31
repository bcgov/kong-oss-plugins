-- Taken from https://github.com/zmartzone/lua-resty-openidc/blob/master/lib/resty/openidc.lua

local string = string

local ngx = ngx
local b64 = ngx.encode_base64
local b64url = require("ngx.base64").encode_base64url
local unb64url = require("ngx.base64").decode_base64url

local log = ngx.log
local DEBUG = ngx.DEBUG

local wrap = ("."):rep(64)

local envelope = "-----BEGIN %s-----\n%s\n-----END %s-----\n"

local function encode_length(length)
    if length < 0x80 then
        return string.char(length)
    elseif length < 0x100 then
        return string.char(0x81, length)
    elseif length < 0x10000 then
        return string.char(0x82, math.floor(length / 0x100), length % 0x100)
    end
    error("Can't encode lengths over 65535")
end

local function encode_bit_string(array)
    local s = "\0" .. array -- first octet holds the number of unused bits
    return "\3" .. encode_length(#s) .. s
end

local function encode_sequence(array, of)
    local encoded_array = array
    if of then
        encoded_array = {}
        for i = 1, #array do
            encoded_array[i] = of(array[i])
        end
    end
    encoded_array = table.concat(encoded_array)
    return string.char(0x30) .. encode_length(#encoded_array) .. encoded_array
end

local function der2pem(data, typ)
    typ = typ:upper() or "CERTIFICATE"
    data = b64(data)
    return string.format(envelope, typ, data:gsub(wrap, "%0\n", (#data - 1) / 64), typ)
end

local function encode_binary_integer(bytes)
    if bytes:byte(1) > 127 then
        -- We currently only use this for unsigned integers,
        -- however since the high bit is set here, it would look
        -- like a negative signed int, so prefix with zeroes
        bytes = "\0" .. bytes
    end
    return "\2" .. encode_length(#bytes) .. bytes
end

local function encode_sequence_of_integer(array)
    return encode_sequence(array, encode_binary_integer)
end

local function openidc_pem_from_rsa_n_and_e(n, e)
    log(DEBUG, "getting PEM public key from n and e parameters of json public key")

    local der_key = {
        unb64url(n),
        unb64url(e)
    }

    local encoded_key = encode_sequence_of_integer(der_key)
    local pem =
        der2pem(
        encode_sequence(
            {
                encode_sequence(
                    {
                        "\6\9\42\134\72\134\247\13\1\1\1" .. "\5\0" -- OID :rsaEncryption -- ASN.1 NULL of length 0
                    }
                ),
                encode_bit_string(encoded_key)
            }
        ),
        "PUBLIC KEY"
    )
    log(DEBUG, "Generated pem key from n and e: ", pem)
    return pem
end

local function convert_kc_key(key)
    return openidc_pem_from_rsa_n_and_e(key.n, key.e)
end

return {
    convert_kc_key = convert_kc_key
}
