local ngx = ngx
local openssl = require("resty.openssl")
local openssl_pkey = require("resty.openssl.pkey")
local kms_aws = require("kong.plugins.trust-kms.backends.aws")
local kms_local = require("kong.plugins.trust-kms.backends.local")
local csr = require("kong.plugins.trust-kms.csr")
local cjson = require "cjson"
local kong_meta = require "kong.meta"
local encode_base64 = ngx.encode_base64
local decode_base64 = ngx.decode_base64
local base64 = require "ngx.base64"

local jwt_decoder = require "kong.plugins.jwt.jwt_parser"
local digest_mod = require("kong.plugins.trust-sign.digest")
local filter = require("kong.plugins.trust-sign.signature_base")
local jwk_sign = require("kong.plugins.trust-sign.sign")
local request_id_get = require("kong.observability.tracing.request_id").get
local log = require("kong.plugins.plugin-log.log")

local PLUGIN_NAME = "trust-kms"

local kong = kong

local function get_ids_from_service()
  local svc = kong.router.get_service()
  -- split svc tags by ":" and find the tags for client and service
  local svc_tags = svc and svc.tags or {}
  local client_tag = ""
  local service_tag = ""
  for _, tag in ipairs(svc_tags) do
    local key,
      value = tag:match("^(.-):(.-)$")
    if key == "client" then
      client_tag = value
    elseif key == "service" then
      service_tag = value
    end
  end
  return client_tag, service_tag
end

local TrustKMSHandler = {
  PRIORITY = 620,
  VERSION = kong_meta.version
}

function TrustKMSHandler:access(conf)
  local operation = conf.operation
  local kms_signature_algorithm = conf.signature_algorithm

  if conf.direction == "request" and operation == "sign" then
    local request = kong.service.request
    local key_id = conf.key_id

    local edge_token = kong.request.get_header(conf.signature_header_key)
    if not edge_token or edge_token == nil then
      return log.exit_with_reason(
        {plugin = PLUGIN_NAME, reason = "missing edge token header '" .. conf.signature_header_key .. "' on the request"},
        403,
        {message = "Missing edge token for signing"}
      )
    end

    --- do the work of the co-signing
    local signature,
      err = do_counter_sign_work(conf, edge_token)
    if err then
      return log.exit_with_reason(
        {plugin = PLUGIN_NAME, reason = "counter-sign failed: " .. (err or "")},
        500,
        {message = "Failed to counter-sign: " .. (err or "")}
      )
    end

    if signature == nil then
      return log.exit_with_reason(
        {plugin = PLUGIN_NAME, reason = "KMS returned no signature for the request edge token"},
        500,
        {message = "Failed to sign message"}
      )
    end

    request.set_header("X-Entity-Sig", signature)
    log.continue_with_reason({plugin = PLUGIN_NAME, reason = "request counter-signed"})
    return
  end

  -- if conf.direction == "request" and operation == "verify" then
  --   local request = kong.service.request
  --   local key_id = conf.key_id

  --   local signature = kong.request.get_header("X-Entity-Sig")
  --   if signature == nil then
  --     return kong.response.exit(400, {message = "X-Entity-Sig header not present"})
  --   end

  --   local edge_token = kong.request.get_header(conf.signature_header_key)
  --   if not edge_token then
  --     return kong.response.exit(403, {message = "Missing edge token for signing"})
  --   end

  --   local signature
  --   if conf.backend == "aws" then
  --     signature = kms.verify(key_id, encode_base64(edge_token), signature, kms_signature_algorithm)
  --   end

  --   if signature == nil then
  --     return kong.response.exit(500, {message = "Failed to get signature from KMS"})
  --   end

  --   request.set_header("X-Entity-Sig-Verified", tostring(signature["SignatureValid"]))
  --   request.set_header("X-Entity-Sig-Algo", signature["SigningAlgorithm"])
  --   return
  -- end

  if operation == "create_key" then
    -- get JSON body of request
    local raw_body = kong.request.get_raw_body()

    -- Then manually parse if needed
    local body_data = cjson.decode(raw_body)

    local country = body_data["country"]
    local org_name = body_data["org_name"]
    local serial_number = body_data["serial_number"]
    local common_name = body_data["common_name"]
    local san = body_data["san"]
    local requester_name = body_data["requester_name"]
    local requester_email = body_data["requester_email"]

    local csr_obj
    local pub_key_obj

    -- create a new Asymmetric KMS key
    if conf.backend == "aws" then
      csr_obj,
        err = csr.new_csr(country, org_name, serial_number, common_name, san)
      if csr_obj == nil then
        return log.exit_with_reason(
          {plugin = PLUGIN_NAME, reason = "failed to build CSR from supplied identity fields: " .. tostring(err)},
          500,
          {message = "Failed to create CSR: " .. err}
        )
      end

      local new_key = kms_aws.create_key(org_name, serial_number, common_name, requester_name, requester_email)
      if new_key == nil then
        return log.exit_with_reason(
          {plugin = PLUGIN_NAME, reason = "AWS KMS create_key call returned no key"},
          500,
          {message = "Failed to create key in KMS"}
        )
      end
      local key_id = new_key["KeyMetadata"]["KeyId"]

      kong.log.warn("Created new KMS key with KeyId: ", cjson.encode(new_key))

      -- Get the public key from KMS for inclusion in CSR
      local pub_key = kms_aws.get_public_key(key_id)

      if pub_key == nil then
        return log.exit_with_reason(
          {plugin = PLUGIN_NAME, reason = "AWS KMS get_public_key returned no key for the newly created KeyId"},
          500,
          {message = "Failed to get public key from KMS"}
        )
      end

      -- Add the public key to CSR
      local key_id = pub_key["body"]["KeyId"]
      local pub_key_der = pub_key["body"]["PublicKey"]

      pub_key_obj,
        err =
        openssl_pkey.new(
        decode_base64(pub_key_der),
        {
          format = "DER",
          type = "pu"
        }
      )
      if pub_key_obj == nil then
        return log.exit_with_reason(
          {plugin = PLUGIN_NAME, reason = "failed to instantiate public key from KMS DER bytes: " .. tostring(err)},
          500,
          {message = "Failed to create public key object: " .. err}
        )
      end

      csr_obj:set_pubkey(pub_key_obj)

      -- Set the signature algorithm in the CSR
      local sig_algorithm = csr.map_kms_to_openssl_algo(kms_signature_algorithm)
      if sig_algorithm == nil then
        return log.exit_with_reason(
          {plugin = PLUGIN_NAME, reason = "unsupported KMS signature algorithm '" .. tostring(kms_signature_algorithm) .. "' has no OpenSSL mapping"},
          500,
          {message = "Failed to map KMS signature algorithm to OpenSSL algorithm " .. kms_signature_algorithm}
        )
      end

      -- Get the TBS (To Be Signed) portion of the CSR
      local tbs_data,
        err = csr.extract_to_be_signed(csr_obj)
      if tbs_data == nil then
        return log.exit_with_reason(
          {plugin = PLUGIN_NAME, reason = "could not extract the to-be-signed bytes from the CSR: " .. tostring(err)},
          500,
          {message = "Failed to extract TBS data from CSR " .. err}
        )
      end

      -- Send to KMS for signing
      local signature_bytes
      local kms_signature = kms_aws.sign(key_id, encode_base64(tbs_data), kms_signature_algorithm)
      if kms_signature == nil then
        return log.exit_with_reason(
          {plugin = PLUGIN_NAME, reason = "AWS KMS sign call returned no signature for the CSR TBS bytes"},
          500,
          {message = "Failed to get signature from KMS", kms_signature = kms_signature}
        )
      end
      local signature_bytes_b64 = kms_signature["Signature"]
      signature_bytes = decode_base64(signature_bytes_b64)
      if signature_bytes == nil then
        return log.exit_with_reason(
          {plugin = PLUGIN_NAME, reason = "could not base64-decode the signature returned by AWS KMS"},
          500,
          {message = "Failed to decode base64 signature from KMS"}
        )
      end

      local ok,
        err = csr.set_signature_algo(csr_obj, sig_algorithm)
      if not ok then
        return log.exit_with_reason(
          {plugin = PLUGIN_NAME, reason = "failed to set signature algorithm on the CSR: " .. tostring(err)},
          500,
          {message = "Failed to set signature algorithm: " .. err}
        )
      end

      -- Set the new signature in the CSR
      local ok,
        err = csr.set_signature(csr_obj, signature_bytes)
      if not ok then
        return log.exit_with_reason(
          {plugin = PLUGIN_NAME, reason = "failed to attach the KMS signature bytes to the CSR: " .. tostring(err)},
          500,
          {message = "Failed to set signature: " .. err}
        )
      end
    else
      -- local key = kms_local.create_key(org_name, serial_number, common_name, requester_name, requester_email)
      local key = kms_local.create_key()
      if key == nil then
        return log.exit_with_reason(
          {plugin = PLUGIN_NAME, reason = "local KMS backend failed to create a signing key"},
          500,
          {message = "Failed to create key for signing"}
        )
      end

      local new_csr_obj,
        err = csr.new_csr_with_key(key, country, org_name, serial_number, common_name, san)
      if new_csr_obj == nil then
        return log.exit_with_reason(
          {plugin = PLUGIN_NAME, reason = "failed to build CSR with the local KMS key: " .. tostring(err)},
          500,
          {message = "Failed to create CSR: " .. err}
        )
      end

      csr_obj = new_csr_obj

      pub_key_obj = kms_local.get_public_key()
    end

    -- Convert CSR to PEM format and return
    local result = csr_obj:tostring("PEM")

    if result == nil then
      return log.exit_with_reason(
        {plugin = PLUGIN_NAME, reason = "failed to serialize the signed CSR to PEM"},
        500,
        {message = "Failed to export to PEM format"}
      )
    end

    return log.exit_with_reason(
      {plugin = PLUGIN_NAME, reason = "returning newly created key and signed CSR"},
      200,
      {
        key_id = key_id,
        signing_algorithm = kms_signature_algorithm,
        csr = result,
        pub_key = pub_key_obj:to_PEM(),
        jwk = pub_key_obj:tostring("public", "JWK"),
        inputs = {
          country = country,
          org_name = org_name,
          serial_number = serial_number,
          common_name = common_name,
          requester_name = requester_name,
          requester_email = requester_email,
          san = san
        }
      }
    )
  end
end

function TrustKMSHandler:header_filter(conf)
  if conf.direction ~= "response" then
    return
  end

  if kong.response.get_source() ~= "service" then
    return
  end

  local kms_signature_algorithm = conf.signature_algorithm

  kong.log.warn("Trust KMS - Header Filter", conf.operation)

  if conf.operation == "sign" then
    local edge_token = kong.response.get_header(conf.signature_header_key)
    if not edge_token then
      return log.exit_with_reason(
        {plugin = PLUGIN_NAME, reason = "missing edge token header '" .. conf.signature_header_key .. "' on the upstream response"},
        403,
        {message = "Missing edge token for signing"}
      )
    end

    -- counter-sign
    local signature,
      err = do_counter_sign_work(conf, edge_token)
    if err then
      return log.exit_with_reason(
        {plugin = PLUGIN_NAME, reason = "counter-sign failed on response: " .. (err or "")},
        500,
        {message = "Failed to counter-sign: " .. (err or "")}
      )
    end

    if signature == nil then
      return log.exit_with_reason(
        {plugin = PLUGIN_NAME, reason = "KMS returned no signature for the response edge token"},
        500,
        {message = "Failed to get signature from KMS"}
      )
    end

    kong.response.set_header("X-Entity-Sig", signature)
    log.continue_with_reason({plugin = PLUGIN_NAME, reason = "response counter-signed"})
    return
  end

  -- if operation == "verify" then
  --   local key_id = conf.key_id

  --   local edge_token = kong.response.get_header(conf.signature_header_key)
  --   if not edge_token then
  --     kong.log.warn("Missing edge token for verification", conf.signature_header_key)
  --     return kong.response.exit(403, {message = "Missing edge token"})
  --   end

  --   local signature = kong.response.get_header("X-Entity-Sig")
  --   if signature == nil then
  --     kong.log.warn("Missing X-Entity-Sig for verification")
  --     return kong.response.exit(400, {message = "X-Entity-Sig header not present"})
  --   end

  --   -- verify counter-signature
  --   local signature = kms.verify(key_id, encode_base64(edge_token), signature, kms_signature_algorithm)

  --   if signature == nil then
  --     kong.log.warn("KMS Verification faileed")
  --     kong.response.set_header("X-Entity-Sig-Error", "Failed to verify signature")
  --     return
  --   end

  --   kong.response.set_header("X-Entity-Sig-Verified", tostring(signature["SignatureValid"]))
  --   kong.response.set_header("X-Entity-Sig-Algo", signature["SigningAlgorithm"])
  --   return
  -- end
end

function do_counter_sign_work(conf, edge_token)
  local key_id = conf.key_id
  local kms_signature_algorithm = conf.signature_algorithm

  -- split edge_token into parts and take the 3rd part
  local tok_header,
    tok_payload,
    tok_signature = edge_token:match("^([^%.]+)%.([^%.]+)%.([^%.]+)$")
  if not tok_header or not tok_payload or not tok_signature then
    return nil, "Invalid edge token format"
  end

  local signature
  if conf.backend == "aws" then
    local aws_signature = kms_aws.sign(key_id, tok_signature, kms_signature_algorithm)
    if aws_signature == nil then
      return nil, "Failed to get signature from KMS"
    end
    signature = aws_signature["Signature"]
    kong.log.warn("Generated signature from KMS: ", cjson.encode(signature))
  else
    local hash_alg = "sha256"
    local signature_raw,
      error = filter.sign(conf, tok_signature, hash_alg)

    -- local signature_raw = kms_local.sign(key_id, tok_signature, kms_signature_algorithm)
    if signature_raw == nil then
      return nil, "Failed to get signature" .. (error or "")
    end

    local verified,
      err = filter.verify(conf, signature_raw, tok_signature, hash_alg)
    if not verified then
      return nil, "Failed to verify signature: " .. (err or "")
    end

    signature = base64.encode_base64url(signature_raw) -- URL-safe, no padding issues
  end

  return signature
end

return TrustKMSHandler
