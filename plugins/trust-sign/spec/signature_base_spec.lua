-- my_module_spec.lua
local my_module = require("signature_base")

describe("my_module", function()
    it("should correctly create signature base", function()
        local result, err = my_module.get_signature_base({
            ["signature"] = 'sig1=:base64signature:',
            ["signature-input"] = 'sig1=("@authority" "extra");keyid="test-key";alg="rsa-pss-sha512"',
            ["host"] = "example.com",
            ["extra"] = "abc"
        }, nil, { extra = true })
        assert.is_string(result[1])
        print("KeyID = ", result[2])
    end)
end)