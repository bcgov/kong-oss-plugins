local ngx = ngx
local decode_base64 = ngx.decode_base64

local my_module = require("digest")

local function to_hex(str)
    return (str:gsub('.', function(c)
        return string.format('%02x',c:byte())
    end))
end

--[[
docker run -ti --rm -v `pwd`:/work -w /work -u root \
  kong:3.9.1 bash

apt-get update && apt-get -y install unzip curl build-essential

luarocks install busted --force

]]
describe("my_module", function()
    it("should correctly validate digest (256)", function()
        local expect = "3fc9b689459d738f8c88a3a48aa9e33542016b7a4052e001aaa536fca74813cb"
        local result = my_module.digest("something", "sha256")
        assert(to_hex(result) == expect)
    end)

    it("should correctly validate digest (512)", function()
        local expect = "983d43ddff6da90f6a5d3b6172446a1ffe228b803fe64fdd5dcfab5646078a896851fe82f623c9d6e5654b3d2f363a04ec17cfb62b607437a9c7c132d511e522"
        local result = my_module.digest("something", "sha512")
        assert(to_hex(result) == expect)
    end)

    it("should parse valid digest header", function()
        local header = "sha256=:P8m2iUWdc4+MiKOkiqnjNUIBa3pAUuABqqU2/KdIE8s=:"
        local alg, digest_bytes, err = my_module.parse(header)

        local match = my_module.digest("something", alg)

        assert(alg == "sha256")
        assert(digest_bytes == match)
    end)

    it("should parse valid digest header (512)", function()
        local header = "sha512=:mD1D3f9tqQ9qXTthckRqH/4ii4A/5k/dXc+rVkYHioloUf6C9iPJ1uVlSz0vNjoE7BfPtitgdDepx8Ey1RHlIg==:"
        local alg, digest_bytes, err = my_module.parse(header)

        local match = my_module.digest("something", alg)

        assert(alg == "sha512")
        assert(digest_bytes == match)
    end)

    it("should fail parsing invalid digest algo in header", function()
        local header = "sha256:P8m2iUWdc4+MiKOkiqnjNUIBa3pAUuABqqU2/KdIE8s=:"
        local alg, digest_bytes, err = my_module.parse(header)
        assert(err == "Invalid Content-Digest header format")
    end)

    it("should fail parsing invalid digest header", function()
        local header = "sha256=:P8m2iUWdc4+MiKOkiqnjNUIBa3pAUuABqqU2/KdIE8s=:"
        local alg, digest_bytes, err = my_module.parse(header)

        local match = my_module.digest("something_else", alg)

        assert(alg == "sha256")
        assert(digest_bytes ~= match)
    end)    
end)