local ltn12 = require("ltn12")
local json = require("cjson")

local _ = require("resty.aws.config").global

local aws = require("resty.aws")

function create_key(org_name)
  -- Configure AWS credentials
  local config = {
    region = os.getenv("AWS_REGION")
  }

  -- Create AWS instance
  local aws_instance = aws(config)

  -- Get KMS service
  local kms = aws_instance:KMS()

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
        }
      }
    }
  )
  if not result then
    kong.log.err("Failed to create KMS key: ", err)
    return nil
  end
  if result["status"] ~= 200 then
    kong.log.error("New key failed. ", json.encode(result))
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
    kong.log.error("KMS signing failed. ", json.encode(result))
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
    kong.log.error("KMS signing failed. ", json.encode(result))
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
