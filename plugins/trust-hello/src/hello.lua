local env_public_key_location = ngx.ssl_certificate

--- Read contents of file from given location
-- @param file_location the file location
-- @return the file contents
local function read_from_file(file_location)
  local content,
    err = pl_file.read(file_location)
  if not content then
    ngx.log(ngx.ERR, "Could not read file contents", err)
    return nil, err
  end
  return content
end

local function collect_data()
  -- In the ssl_cert phase, you can access certificate information
  local ssl = require "ngx.ssl"

  -- Get the server certificate being used
  local cert,
    err = ssl.get_cert()
  if not cert then
    kong.log.err("Failed to get SSL certificate: ", err)
    return
  end

  -- You can then parse the certificate
  local x509 = require "resty.openssl.x509"
  local parsed_cert,
    err = x509.new(cert, "DER")
  if not parsed_cert then
    kong.log.err("Failed to parse certificate: ", err)
    return
  end

  -- Access certificate information
  local subject = parsed_cert:get_subject_name()
  local issuer = parsed_cert:get_issuer_name()

  return {
    subject = subject:as_string(),
    issuer = issuer:as_string()
  }
end

function inspect_cert()
  local cert = read_from_file(env_public_key_location)

  -- You can then parse the certificate
  local x509 = require "resty.openssl.x509"
  local parsed_cert,
    err = x509.new(cert, "DER")
  if not parsed_cert then
    kong.log.err("Failed to parse certificate: ", err)
    return
  end

  -- Access certificate information
  local subject = parsed_cert:get_subject_name()
  local issuer = parsed_cert:get_issuer_name()

  return {
    subject = subject:as_string(),
    issuer = issuer:as_string()
  }
end

return {
  collect_data = collect_data,
  inspect_cert = inspect_cert
}
