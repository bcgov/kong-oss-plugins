local keycloak_keys = require("kong.plugins.jwt-keycloak.keycloak_keys")
local jwt_decoder = require "kong.plugins.jwt.jwt_parser"
local cjson_safe = require "cjson.safe"
local openssl_pkey = require "resty.openssl.pkey"

describe(
  "tokens",
  function()
    it(
      "should get parse key",
      function()
        local jwks_json =
          '{"keys":[{"kid":"gFqFV9rrMarzqRfXcvPLHZSWdxe9fW6ML4wFD5hmsi8","kty":"RSA","alg":"RSA-OAEP","use":"enc","n":"30PH0l1hBxk9SaeBKhM41gj7qQpQ9OIThxajjindAbn_JqnqbeZdZPvUf7PhPYFcZ7Gb0Q_Bd0Xewcxlor_gARcd2QtjFgYwyXgIE7352ZCRQYulGIgi3htPhRcVoIgIfwKurnfg701o7h5QW4FQi5C7bh7cTMme48_3kzceOILx9aA6hOou7khg5Qm2m5rbBc-Sf6xB6H54WbLMSyB8l4d0GuR9L3c_Jx1kpeHnnJM7cv6220hIuHqpO7aWMt8BX81DtyGL4DAvsFr2lRE2o2xNyxLByLcpEt2q_1upPzz0BuzGw_X30JyyB-NcQZ77jFAnDrVeZ8vrvw_geD9Ikw","e":"AQAB","x5c":["MIIClTCCAX0CBgGVY+1KwDANBgkqhkiG9w0BAQsFADAOMQwwCgYDVQQDDANlMmUwHhcNMjUwMzA1MDEyOTEwWhcNMzUwMzA1MDEzMDUwWjAOMQwwCgYDVQQDDANlMmUwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDfQ8fSXWEHGT1Jp4EqEzjWCPupClD04hOHFqOOKd0Buf8mqept5l1k+9R/s+E9gVxnsZvRD8F3Rd7BzGWiv+ABFx3ZC2MWBjDJeAgTvfnZkJFBi6UYiCLeG0+FFxWgiAh/Aq6ud+DvTWjuHlBbgVCLkLtuHtxMyZ7jz/eTNx44gvH1oDqE6i7uSGDlCbabmtsFz5J/rEHofnhZssxLIHyXh3Qa5H0vdz8nHWSl4eeckzty/rbbSEi4eqk7tpYy3wFfzUO3IYvgMC+wWvaVETajbE3LEsHItykS3ar/W6k/PPQG7MbD9ffQnLIH41xBnvuMUCcOtV5ny+u/D+B4P0iTAgMBAAEwDQYJKoZIhvcNAQELBQADggEBANnVy1wrIdFBgqCOKEQPbqAU5UOV7su0FI6HOF0MQi0nNU3pdfBjAQ6cl7qY0qMCR/G/PSYeXnEVZZXvabHyGVQcSooz5/bkVCYJQDv3FHGkUYcnnOGoG1tw97IZcN8/UbIURu3YX3P5WreRx0OwdngYsb53lMYGeItuic25yR0V9r3o4K7nYSjimpaoGIZbwWGNqXTieCMFvT1Bt13irAieNFvrGV2TAFT+BCzRo7RAm3zCS178FQVcwEY1iPm3etG5edu2KTshjW9lxs6ZF206wSCMs3EDah4L7tuxHKbEtlSLcyhtUTVrttT6hMyQmn1SsAT5TlK5LGQ/V9Tptmg="],"x5t":"5a0CNmjazaHSwyaduVkeBS7ruNk","x5t#S256":"VGRPGcJ5YtklWkPkmaKEIaHlVF-D3pBEkaqeQ4WvvPw"},{"kid":"h0Ckw784gH2-H0HeI-WS5z42G_YaXO0A7j5gd204NEk","kty":"RSA","alg":"RS256","use":"sig","n":"xBcw9FuwMgkwbWClsauxoPBiqIXmWQ2RRdpJPhqf-rdVdUv2vmk5NXE7jUo2r0QzzSONHzEjyaPYo0bDo1BcQkjkuAa8bImveuBWYBOQOqedIavlGgDeODDimE4Adu7_31dPmj3P_rGTZQIKAQg_48cXSna0cLmiItnMkboUxbgzOc0uBGu-5BjLZGF1ELCfQCvj22IvFuFQDJD3HUmQYdwjoWXL8fFB2M_cJaTSmTU18bYiL2o1-Ty9f3F3k42Sy4OoiQD4ksZxyLpCdHpfZhSb028-_G3yktULZFbhN6I3Y2Loch0HKM5KmIJ5uOOpkGOK_gw3IDpBf3y3bQms5Q","e":"AQAB","x5c":["MIIClTCCAX0CBgGVY+1KmjANBgkqhkiG9w0BAQsFADAOMQwwCgYDVQQDDANlMmUwHhcNMjUwMzA1MDEyOTEwWhcNMzUwMzA1MDEzMDUwWjAOMQwwCgYDVQQDDANlMmUwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDEFzD0W7AyCTBtYKWxq7Gg8GKoheZZDZFF2kk+Gp/6t1V1S/a+aTk1cTuNSjavRDPNI40fMSPJo9ijRsOjUFxCSOS4Brxsia964FZgE5A6p50hq+UaAN44MOKYTgB27v/fV0+aPc/+sZNlAgoBCD/jxxdKdrRwuaIi2cyRuhTFuDM5zS4Ea77kGMtkYXUQsJ9AK+PbYi8W4VAMkPcdSZBh3COhZcvx8UHYz9wlpNKZNTXxtiIvajX5PL1/cXeTjZLLg6iJAPiSxnHIukJ0el9mFJvTbz78bfKS1QtkVuE3ojdjYuhyHQcozkqYgnm446mQY4r+DDcgOkF/fLdtCazlAgMBAAEwDQYJKoZIhvcNAQELBQADggEBABnwhjNP5JoQzHUkAZSdOujI/d8md18YpszOKZoLYOv5dXvTt1FbdLb8i2AtJ4jDmdTLs0C2YvZ7N2dQbYCQqU/8lYvapNzYTHh8auTFKlf8AZaYuseLxC9ZHWDJT47OmOggEDYoxjMGCqeI5bVibH/WhWxYR7xQlgNYJM+CmSFgVmqeXf2WPKkpZJfVm5SKjybZ/cyJopEz1cJNQHuknFJXq4OtDr3A+7/aAxb+LlvnThMaL1dUGAhLdIuBs9M4ekBdz1tPQwBDzu6rTzZpgFJRylM62uHnHQX0hKiNCwgZbepHAgXIjVNX4xXEPx3875hr0EpUl5kkkA23F1Tj+WQ="],"x5t":"uGffxiIeJivxeuffzR3BWaWmcR0","x5t#S256":"v9WQzNb8ec4hd2nldffMz_5o62iGU9UcfG-_9kKr4Lw"}]}'

        local jwks = cjson_safe.decode(jwks_json)

        local public_keys,
          err = keycloak_keys.get_issuer_key_from_jwks_content(jwks)
        assert.same(err, nil)

        local token =
          "eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJoMENrdzc4NGdIMi1IMEhlSS1XUzV6NDJHX1lhWE8wQTdqNWdkMjA0TkVrIn0.eyJleHAiOjE3NDExMzkxOTgsImlhdCI6MTc0MTEzODg5OCwianRpIjoiNmZjOTk2NmItYzYwMi00MTE0LWJlMjItMDAyZGQ0NjA3MWVjIiwiaXNzIjoiaHR0cDovL2tleWNsb2FrLmxvY2FsdGVzdC5tZTo5MDgxL2F1dGgvcmVhbG1zL2UyZSIsInN1YiI6IjUxZjhiYTkwLWRkNGUtNGRlMy1hODZlLTE1Y2E2MGQ2ODYxYiIsInR5cCI6IkJlYXJlciIsImF6cCI6InRlc3QtY2xpZW50LUQ0OTEzIiwiYWNyIjoiMSIsInNjb3BlIjoib3BlbmlkIHByb2ZpbGUgZW1haWwiLCJjbGllbnRIb3N0IjoiMTcyLjI5LjAuMSIsImNsaWVudElkIjoidGVzdC1jbGllbnQtRDQ5MTMiLCJlbWFpbF92ZXJpZmllZCI6ZmFsc2UsInByZWZlcnJlZF91c2VybmFtZSI6InNlcnZpY2UtYWNjb3VudC10ZXN0LWNsaWVudC1kNDkxMyIsImNsaWVudEFkZHJlc3MiOiIxNzIuMjkuMC4xIn0.YFSjSizMUJDFaQHSCoV0P-WnrrYfaSxwp19Hwj51qfNgEdRex9je6b5xlohO0Z60pSZV4AJHYK1bytZu8UcuEawNq5SdkR9Briztv2B8QVi3DhyVWzgglX0tGHSVOu5HxykhUqSHvSLl5BZBJaNSWvnxU1cQa-q8UDwafi8fICITRU3V-PPDD1vQ5pD8cn4QZ-5QxeqhygCicJK4SJBerSmu4Ypz3bZvuux6QC4NF0T1DCcj0AK062h1RIV6hpknL_N9d8y71CgoGknLKl3XazUfqipWf95jwuH2-ymTl0sAS0-w2SvWT65Ek_hd-k2RAKc46a5Vae_Vl2cUtzDXdg"

        local jwt,
          err = jwt_decoder:new(token)
        assert.same(err, nil)

        local header = jwt.header
        print(header.kid)

        -- Verify signatures
        local ok = false
        for _, k in ipairs(public_keys) do
          print("EVAL")
          print(k)
          -- local pkey,
          --   _ = openssl_pkey.new(key)
          -- print(pkey)
          -- assert(pkey, "Consumer Public Key is Invalid")

          local function verify_sig(sig_key)
            print(sig_key)
            local verified = jwt:verify_signature(sig_key)

            if verified then
              print("Valid!")
              ok = true
            else
              print("Invalid")
            end
          end
          verify_sig(k)
          -- local success,
          --   err = pcall(verify_sig, k)
          -- if not success then
          --   print("Invalid" .. err)
          -- end
          if ok then
            break
          end
        end
        assert.same(true, ok, "JWT signature check failed")
      end
    )
  end
)
