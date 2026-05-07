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

function create_key(org_name, serial_number, common_name, requester_name, requester_email)
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

function disable_key(key_id)
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

function sign(key_id, message, algo)
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

function verify(key_id, message, signature, algo)
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

function get_public_key(key_id)
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

return {
  create_key = create_key,
  disable_key = disable_key,
  sign = sign,
  verify = verify,
  get_public_key = get_public_key
}
