local openssl_pkey = require("resty.openssl.pkey")
local openssl_x509_name = require("resty.openssl.x509.name")
local openssl_x509_csr = require "resty.openssl.x509.csr"
local openssl_extension = require("resty.openssl.x509.extension")
local openssl_extensions = require("resty.openssl.x509.extensions")
local ffi = require("ffi")
local C = ffi.C

function new_csr(country, org_name, serial_number, common_name, san)
  -- Step 1: Generate a key pair locally (public/private)
  local key =
    openssl_pkey.new(
    {
      type = "RSA",
      bits = 2048
    }
  )

  -- Step 2: Create the CSR
  local subject = openssl_x509_name.new()
  subject:add("C", country)
  subject:add("O", org_name .. "/serialNumber=" .. serial_number)
  subject:add("CN", common_name)
  local csr,
    err = openssl_x509_csr.new()
  if not csr then
    kong.log.err("failed to create CSR instance: ", err)
    return nil, err
  end

  csr:set_subject_name(subject)
  csr:set_pubkey(key)

  -- -- -- Add an extension request attribute (common and useful)
  local altname = openssl_extension.new("subjectAltName", "DNS:" .. san)

  -- Add extensions as an attribute
  local ok,
    err = csr:set_extension(altname)
  if not ok then
    kong.log.err("Failed to set extension: ", err)
    return nil, err
  end

  -- -- Add Key Usage extension
  -- local key_usage_ext = openssl_extension.new("keyUsage", "critical,digitalSignature,keyEncipherment")

  -- local key_usage_ext,
  --   err =
  --   openssl_extension.from_data(
  --   {
  --     ["1.2.840.113549.1.9.14"] = {
  --       -- extensionRequest OID
  --       ["2.5.29.15"] = "critical,digitalSignature,keyEncipherment" -- keyUsage OID
  --     }
  --   }
  -- )
  -- if key_usage_ext == nil then
  --   kong.log.err("Failed to create keyUsage extension", err)
  --   return nil, "Failed to create keyUsage extension"
  -- end

  -- -- local key_usage_ext =
  -- --   openssl_extension.new(
  -- --   {
  -- --     name = "keyUsage",
  -- --     value = "digitalSignature,nonRepudiation,keyEncipherment",
  -- --     critical = true
  -- --   }
  -- -- )
  -- kong.log.warn("Created keyUsage extension: " .. tostring(key_usage_ext))

  -- local ok,
  --   err = csr:set_extension(key_usage_ext)
  -- if not ok then
  --   kong.log.err("Failed to set keyUsage: ", err)
  --   return nil, err
  -- end
  -- kong.log.warn("Added keyUsage extension to CSR")

  -- Requested Extensions:
  --   X509v3 Subject Alternative Name:
  --       DNS:CCIAlt
  --   X509v3 Key Usage:
  --       Non Repudiation, Certificate Sign

  -- Create an extensions stack
  -- local exts = openssl_extensions.new()

  -- -- Add extensions to the stack
  -- local key_usage = openssl_extension.new("keyUsage", "critical,digitalSignature,keyEncipherment")
  -- exts:add(key_usage)

  -- local ext_key_usage = openssl_extension.new("extendedKeyUsage", "serverAuth,clientAuth")
  -- exts:add(ext_key_usage)

  -- -- Now add the extensions stack to CSR
  -- local ok,
  --   err = csr:set_extension(exts)
  -- if not ok then
  --   kong.log.err("Failed to set extensions stack: ", err)
  --   return nil, err
  -- end

  -- Sign the CSR with the local private key (standard CSR creation)
  csr:sign(key)

  return csr
end

function extract_to_be_signed(csr_obj)
  -- Encode the certificationRequestInfo to DER
  ffi.cdef [[
    typedef struct x509_req_st X509_REQ;
    typedef struct X509_req_info_st X509_REQ_INFO;
    
    // Get the req_info from X509_REQ
    int i2d_re_X509_REQ_tbs(X509_REQ *req, unsigned char **out);
  ]]

  -- Get the internal X509_REQ structure
  local ctx = csr_obj.ctx

  -- Try to get TBS data using i2d_re_X509_REQ_tbs (OpenSSL 1.1.0+)
  local der_len = C.i2d_re_X509_REQ_tbs(ctx, nil)

  if der_len < 0 then
    return nil, "failed to get length of certificationRequestInfo"
  end

  local buf = ffi.new("unsigned char[?]", der_len)
  local ptr = ffi.new("unsigned char*[1]", buf)
  local final_len = C.i2d_re_X509_REQ_tbs(ctx, ptr)

  if final_len < 0 then
    return nil, "failed to encode certificationRequestInfo"
  end

  kong.log.warn("Extracted TBS data length: " .. final_len)
  return ffi.string(buf, final_len)
end

local function get_nid(txt)
  local objects = require("resty.openssl.objects")

  -- Get the NID based on text
  return objects.txt2nid(txt)

  -- See https://github.com/openssl/openssl/blob/master/include/openssl/obj_mac.h

  -- Common signature algorithm names:
  -- "sha256WithRSAEncryption"
  -- "sha384WithRSAEncryption"
  -- "sha512WithRSAEncryption"
  -- "ecdsa-with-SHA256"
  -- "ecdsa-with-SHA384"
  -- "ecdsa-with-SHA512"
end

function set_signature_algo(csr_obj, algo)
  ffi.cdef [[
    typedef struct x509_req_st X509_REQ;
    typedef struct X509_algor_st X509_ALGOR;
    typedef struct asn1_string_st ASN1_BIT_STRING;
    typedef struct asn1_object_st ASN1_OBJECT;
    
    // Get TBS data
    int i2d_re_X509_REQ_tbs(X509_REQ *req, unsigned char **out);
    
    // Access signature components
    void X509_REQ_get0_signature(const X509_REQ *req, const ASN1_BIT_STRING **psig, const X509_ALGOR **palg);
    
    // Manipulate ASN1_BIT_STRING
    int ASN1_BIT_STRING_set(ASN1_BIT_STRING *a, unsigned char *d, int length);
    
    // Algorithm functions
    X509_ALGOR *X509_ALGOR_new();
    void X509_ALGOR_free(X509_ALGOR *alg);
    void X509_ALGOR_set0(X509_ALGOR *alg, ASN1_OBJECT *aobj, int ptype, void *pval);
    const ASN1_OBJECT *OBJ_nid2obj(int n);
    
    // For setting algorithm in the request
    int X509_REQ_set1_signature_algo(X509_REQ *req, X509_ALGOR *palg);
    
    // Alternative: use i2d/d2i to rebuild the CSR
    int i2d_X509_REQ(X509_REQ *a, unsigned char **out);
    X509_REQ *d2i_X509_REQ(X509_REQ **a, const unsigned char **in, long len);
    
    // Memory allocation
    void *OPENSSL_malloc(size_t num);
    void OPENSSL_free(void *ptr);
  ]]

  -- Get the internal X509_REQ structure
  local ctx = csr_obj.ctx

  -- Step 4: Set signature algorithm
  local alg = C.X509_ALGOR_new()
  if alg == nil then
    return false, "Failed to create algorithm"
  end

  local algo_nid = get_nid(algo)
  kong.log.warn("Setting signature algorithm NID: " .. algo_nid)

  -- Use ASN1_OBJECT instead of void*
  local obj = C.OBJ_nid2obj(algo_nid)
  if obj == nil then
    C.X509_ALGOR_free(alg)
    return false, "Failed to get algorithm object"
  end

  -- Cast away const (this is safe because X509_ALGOR_set0 doesn't modify it)
  local obj_ptr = ffi.cast("ASN1_OBJECT*", obj)
  C.X509_ALGOR_set0(alg, obj_ptr, 5, nil) -- 5 = V_ASN1_NULL

  local ok = C.X509_REQ_set1_signature_algo(ctx, alg)
  C.X509_ALGOR_free(alg)

  if ok ~= 1 then
    return false, "Failed to set signature algorithm"
  end

  return true
end

function set_signature(csr_obj, signature_bytes)
  ffi.cdef [[
    typedef struct x509_req_st X509_REQ;
    typedef struct X509_algor_st X509_ALGOR;
    typedef struct asn1_string_st ASN1_BIT_STRING;
    typedef struct asn1_object_st ASN1_OBJECT;
    
    // Get TBS data
    int i2d_re_X509_REQ_tbs(X509_REQ *req, unsigned char **out);
    
    // Access signature components
    void X509_REQ_get0_signature(const X509_REQ *req, const ASN1_BIT_STRING **psig, const X509_ALGOR **palg);
    
    // Manipulate ASN1_BIT_STRING
    int ASN1_BIT_STRING_set(ASN1_BIT_STRING *a, unsigned char *d, int length);
    
    // Algorithm functions
    X509_ALGOR *X509_ALGOR_new();
    void X509_ALGOR_free(X509_ALGOR *alg);
    void X509_ALGOR_set0(X509_ALGOR *alg, ASN1_OBJECT *aobj, int ptype, void *pval);
    const ASN1_OBJECT *OBJ_nid2obj(int n);
    
    // For setting algorithm in the request
    int X509_REQ_set1_signature_algo(X509_REQ *req, X509_ALGOR *palg);
    
    // Alternative: use i2d/d2i to rebuild the CSR
    int i2d_X509_REQ(X509_REQ *a, unsigned char **out);
    X509_REQ *d2i_X509_REQ(X509_REQ **a, const unsigned char **in, long len);
    
    // Memory allocation
    void *OPENSSL_malloc(size_t num);
    void OPENSSL_free(void *ptr);
  ]]

  -- Get the internal X509_REQ structure
  local ctx = csr_obj.ctx

  -- Set the signature value using ASN1_BIT_STRING_set
  local sig_ptr = ffi.new("const ASN1_BIT_STRING*[1]")
  local alg_ptr = ffi.new("const X509_ALGOR*[1]")
  C.X509_REQ_get0_signature(ctx, sig_ptr, alg_ptr)

  local sig_bitstring = ffi.cast("ASN1_BIT_STRING*", sig_ptr[0])

  -- Use ffi.new to allocate memory that will be automatically managed
  local sig_len = #signature_bytes
  local sig_data = ffi.new("unsigned char[?]", sig_len)
  ffi.copy(sig_data, signature_bytes, sig_len)

  -- Set the signature
  local ok = C.ASN1_BIT_STRING_set(sig_bitstring, sig_data, sig_len)
  if ok ~= 1 then
    return false, "Failed to set signature"
  end

  return true
end

function map_kms_to_openssl_algo(kms_algo)
  local mapping = {
    ["RSASSA_PKCS1_V1_5_SHA_256"] = "sha256WithRSAEncryption",
    ["RSASSA_PKCS1_V1_5_SHA_384"] = "sha384WithRSAEncryption",
    ["RSASSA_PKCS1_V1_5_SHA_512"] = "sha512WithRSAEncryption",
    ["RSASSA_PSS_SHA_256"] = "sha256WithRSAEncryption",
    ["RSASSA_PSS_SHA_384"] = "sha384WithRSAEncryption",
    ["RSASSA_PSS_SHA_512"] = "sha512WithRSAEncryption",
    ["ECDSA_SHA_256"] = "ecdsa-with-SHA256",
    ["ECDSA_SHA_384"] = "ecdsa-with-SHA384",
    ["ECDSA_SHA_512"] = "ecdsa-with-SHA512"
  }

  return mapping[kms_algo]
end

return {
  new_csr = new_csr,
  extract_to_be_signed = extract_to_be_signed,
  set_signature_algo = set_signature_algo,
  set_signature = set_signature,
  map_kms_to_openssl_algo = map_kms_to_openssl_algo
}
