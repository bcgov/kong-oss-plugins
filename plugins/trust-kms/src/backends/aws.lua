local ltn12 = require("ltn12")
local json = require("cjson")

local digest_mod = require("kong.plugins.trust-sign.digest")

local _ = require("resty.aws.config").global

local aws = require("resty.aws")

-- Define the characters to use
local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

local function random_str(len)
  local result = ""
  for i = 1, len do
    local rand = math.random(1, #chars)
    result = result .. chars:sub(rand, rand)
  end
  return result
end

local function create_key(org_name, serial_number, common_name, requester_name, requester_email)
  -- Configure AWS credentials
  local config = {
    region = os.getenv("AWS_REGION")
  }

  -- Create AWS instance
  local aws_instance = aws(config)

  -- Get KMS service
  local kms = aws_instance:KMS()

  if kms == nil then
    kong.log.err("Failed to create KMS client - check AWS configuration")
    return nil
  end

  -- Create key
  local result,
    err =
    kms:createKey(
    {
      Description = "Key for " .. org_name .. " created from Kong Trust KMS Plugin",
      KeyUsage = "SIGN_VERIFY",
      KeySpec = "ECC_NIST_P521",
      CustomerMasterKeySpec = "ECC_NIST_P521", -- deprecated, but some SDKs still use it
      Origin = "AWS_KMS",
      Tags = {
        {
          TagKey = "CreatedBy",
          TagValue = "KongTrustKMSPlugin"
        },
        {
          TagKey = "Organization",
          TagValue = org_name
        },
        {
          TagKey = "SerialNumber",
          TagValue = serial_number
        },
        {
          TagKey = "CommonName",
          TagValue = common_name
        },
        {
          TagKey = "RequesterName",
          TagValue = requester_name
        },
        {
          TagKey = "RequesterEmail",
          TagValue = requester_email
        }
      }
    }
  )
  if not result then
    kong.log.err("Failed to create KMS key: ", err)
    return nil
  end
  if result["status"] ~= 200 then
    kong.log.err("New key failed. ", json.encode(result))
    return nil
  end

  --
  -- Create Alias
  --

  local key_id = result["body"]["KeyMetadata"]["KeyId"]

  -- [a-zA-Z0-9:/_-]
  local alias_name = "alias/" .. serial_number .. "/" .. random_str(4)

  local alias_result,
    err =
    kms:createAlias(
    {
      AliasName = alias_name,
      TargetKeyId = key_id
    }
  )

  if not alias_result then
    kong.log.err("Failed to create KMS key alias: ", err)
    return nil
  end
  if alias_result["status"] ~= 200 then
    kong.log.err("Create alias failed. ", json.encode(alias_result))
    return nil
  end

  return result["body"]
end

local function disable_key(key_id)
  -- Configure AWS credentials
  local config = {
    region = os.getenv("AWS_REGION")
  }

  -- Create AWS instance
  local aws_instance = aws(config)

  -- Get KMS service
  local kms = aws_instance:KMS()

  if kms == nil then
    kong.log.err("Failed to create KMS client - check AWS configuration")
    return nil
  end

  -- Disable key
  local result,
    err =
    kms:disableKey(
    {
      KeyId = key_id
    }
  )
  if not result then
    kong.log.err("Failed to disable KMS key: ", err)
    return nil
  end
  return result
end

local function sign(key_id, message, algo)
  -- Configure AWS credentials
  local config = {
    region = os.getenv("AWS_REGION")
  }

  -- Create AWS instance
  local aws_instance = aws(config)

  -- Get KMS service
  local kms = aws_instance:KMS()

  if kms == nil then
    kong.log.err("Failed to create KMS client - check AWS configuration")
    return nil
  end

  kong.log.warn("Signing message with KMS key ", key_id, " and algorithm ", algo)

  -- Sign message
  local result,
    err =
    kms:sign(
    {
      KeyId = key_id,
      Message = message,
      SigningAlgorithm = algo,
      MessageType = "RAW"
    }
  )
  if not result then
    kong.log.err("Failed to sign message: ", err)
    return nil
  end
  if result["status"] ~= 200 then
    kong.log.err("KMS signing failed. ", json.encode(result))
    return nil
  end

  return result["body"]
end

local function verify(key_id, message, signature, algo)
  -- Configure AWS credentials
  local config = {
    region = os.getenv("AWS_REGION")
  }

  -- Create AWS instance
  local aws_instance = aws(config)

  -- Get KMS service
  local kms = aws_instance:KMS()

  if kms == nil then
    kong.log.err("Failed to create KMS client - check AWS configuration")
    return nil
  end

  -- Verify signature
  local result,
    err =
    kms:verify(
    {
      KeyId = key_id,
      Message = message,
      Signature = signature,
      SigningAlgorithm = algo,
      MessageType = "RAW"
    }
  )
  if not result then
    kong.log.err("Failed to verify signature: ", err)
    return nil
  end
  if result["status"] ~= 200 then
    kong.log.err("KMS verification failed. ", json.encode(result))
    return nil
  end

  return result["body"]
end

local function get_public_key(key_id)
  -- Configure AWS credentials
  local config = {
    region = os.getenv("AWS_REGION")
  }

  -- Create AWS instance
  local aws_instance = aws(config)

  -- Get KMS service
  local kms = aws_instance:KMS()

  if kms == nil then
    kong.log.err("Failed to create KMS client - check AWS configuration")
    return nil
  end

  -- Get public key
  local result,
    err =
    kms:getPublicKey(
    {
      KeyId = key_id
    }
  )
  if not result then
    kong.log.err("Failed to get public key: ", err)
    return nil
  end
  return result
end

-- Normalize AWS public-key material to the same contract as the local backend.
local function get_signing_key(conf)
  local result = get_public_key(conf.key_id)
  if not result or result.status ~= 200 or not result.body then
    return nil, "Failed to get public key from AWS KMS"
  end
  local body = result.body
  if body.KeyUsage ~= "SIGN_VERIFY" then return nil, "AWS key is not a signing key" end
  local supported = false
  for _, algorithm in ipairs(body.SigningAlgorithms or {}) do
    if algorithm == conf.signature_algorithm then supported = true end
  end
  if not supported then return nil, "AWS key does not support the configured signing algorithm" end
  if not body.KeyId or body.KeyId == "" then return nil, "AWS public key response has no key identifier" end
  local der = type(body.PublicKey) == "string" and ngx.decode_base64(body.PublicKey)
  if not der then return nil, "Invalid AWS public key encoding" end
  local key, err = require("resty.openssl.pkey").new(der, {format = "DER", type = "pu"})
  if not key then return nil, "Invalid AWS public key: " .. tostring(err) end
  local public_pem, export_err = key:to_PEM("public")
  if not public_pem then return nil, "Unable to export AWS public key: " .. tostring(export_err) end
  -- Pin signing to the returned key ARN, not a mutable configured alias.
  return { public_key = public_pem, key_id = body.KeyId }
end

return {
  get_signing_key = get_signing_key,
  create_key = create_key,
  disable_key = disable_key,
  sign = sign,
  verify = verify,
  get_public_key = get_public_key
}
