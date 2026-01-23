local ngx = ngx
local openssl = require("resty.openssl")
local openssl_pkey = require("resty.openssl.pkey")
local kms = require("kong.plugins.trust-kms.kms")
local csr = require("kong.plugins.trust-kms.csr")
local cjson = require "cjson"
local kong_meta = require "kong.meta"
local encode_base64 = ngx.encode_base64
local decode_base64 = ngx.decode_base64

local jwt_decoder = require "kong.plugins.jwt.jwt_parser"
local digest_mod = require("kong.plugins.trust-sign.digest")
local filter = require("kong.plugins.trust-sign.signature_base")
local jwk_sign = require("kong.plugins.trust-sign.sign")
local request_id_get = require("kong.observability.tracing.request_id").get

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
  PRIORITY = 940,
  VERSION = kong_meta.version
}

function TrustKMSHandler:access(conf)
  local operation = conf.operation
  local kms_signature_algorithm = conf.signature_algorithm

  if operation == "sign" then
    local request = kong.service.request
    local key_id = conf.keyid

    local raw_body = kong.request.get_raw_body()
    local signature = kms.sign(key_id, encode_base64(raw_body), kms_signature_algorithm)

    if signature == nil then
      return kong.response.exit(500, {message = "Failed to get signature from KMS"})
    end

    request.set_header("X-Entity-Sig", signature["Signature"])
    return
  end

  if operation == "verify" then
    local request = kong.service.request
    local key_id = conf.keyid

    local signature = kong.request.get_header("X-Entity-Sig")
    if signature == nil then
      return kong.response.exit(400, {message = "X-Entity-Sig header not present"})
    end

    local raw_body = kong.request.get_raw_body()
    local signature = kms.verify(key_id, encode_base64(raw_body), signature, kms_signature_algorithm)

    if signature == nil then
      return kong.response.exit(500, {message = "Failed to get signature from KMS"})
    end

    request.set_header("X-Entity-Sig-Verified", tostring(signature["SignatureValid"]))
    request.set_header("X-Entity-Sig-Algo", signature["SigningAlgorithm"])
    return
  end

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

    -- create a new Asymmetric KMS key
    local new_key = kms.create_key(org_name, serial_number)
    if new_key == nil then
      return kong.response.exit(500, {message = "Failed to create key in KMS"})
    end
    local key_id = new_key["KeyMetadata"]["KeyId"]

    kong.log.warn("Created new KMS key with KeyId: ", cjson.encode(new_key))

    local csr_obj,
      err = csr.new_csr(country, org_name, serial_number, common_name, san)
    if csr_obj == nil then
      return kong.response.exit(500, {message = "Failed to create CSR: " .. err})
    end

    -- Get the public key from KMS for inclusion in CSR
    local pub_key = kms.get_public_key(key_id)

    if pub_key == nil then
      return kong.response.exit(500, {message = "Failed to get public key from KMS"})
    end

    -- Add the public key to CSR
    local key_id = pub_key["body"]["KeyId"]
    local pub_key_der = pub_key["body"]["PublicKey"]

    local pub_key_obj,
      err =
      openssl_pkey.new(
      decode_base64(pub_key_der),
      {
        format = "DER",
        type = "pu"
      }
    )
    if pub_key_obj == nil then
      return kong.response.exit(500, {message = "Failed to create public key object: " .. err})
    end

    csr_obj:set_pubkey(pub_key_obj)

    -- Get the TBS (To Be Signed) portion of the CSR
    local tbs_data,
      err = csr.extract_to_be_signed(csr_obj)
    if tbs_data == nil then
      return kong.response.exit(500, {message = "Failed to extract TBS data from CSR " .. err})
    end

    -- Send to KMS for signing
    local kms_signature = kms.sign(key_id, encode_base64(tbs_data), kms_signature_algorithm)
    if kms_signature == nil then
      return kong.response.exit(500, {message = "Failed to get signature from KMS", kms_signature = kms_signature})
    end

    local signature_bytes_b64 = kms_signature["Signature"]
    local signature_bytes = decode_base64(signature_bytes_b64)
    if signature_bytes == nil then
      return kong.response.exit(500, {message = "Failed to decode base64 signature from KMS"})
    end

    -- Set the signature algorithm in the CSR
    local sig_algorithm = csr.map_kms_to_openssl_algo(kms_signature_algorithm)
    if sig_algorithm == nil then
      return kong.response.exit(
        500,
        {message = "Failed to map KMS signature algorithm to OpenSSL algorithm " .. kms_signature_algorithm}
      )
    end

    local ok,
      err = csr.set_signature_algo(csr_obj, sig_algorithm)
    if not ok then
      return kong.response.exit(500, {message = "Failed to set signature algorithm: " .. err})
    end

    -- Set the new signature in the CSR
    local ok,
      err = csr.set_signature(csr_obj, signature_bytes)
    if not ok then
      return kong.response.exit(500, {message = "Failed to set signature: " .. err})
    end

    -- Convert CSR to PEM format and return
    local result = csr_obj:tostring("PEM")

    if result == nil then
      return kong.response.exit(500, {message = "Failed to export to PEM format"})
    end

    return kong.response.exit(
      200,
      {
        key_id = key_id,
        signing_algorithm = kms_signature_algorithm,
        csr = result,
        pub_key = pub_key_obj:to_PEM(),
        jwk = cjson.decode(pub_key_obj:tostring("public", "JWK")),
        inputs = {
          country = country,
          org_name = org_name,
          serial_number = serial_number,
          common_name = common_name,
          san = san
        }
      }
    )
  end
end

return TrustKMSHandler
