[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]
    $ScepmanUrl,
    [Parameter]
    [string]
    $certificateSubject = "CN=MyCert",
    [Parameter]
    [string]
    $password = "password"
)

# Create a new RSA key pair and certificate request using .NET
$rsakey = [System.Security.Cryptography.RSA]::Create()
$csr = new-object System.Security.Cryptography.X509Certificates.CertificateRequest(
  $certificateSubject, $rsakey, 
  [System.Security.Cryptography.HashAlgorithmName]::SHA256, 
  [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
$binCsr = $csr.CreateSigningRequest()
[System.IO.File]::WriteAllBytes("mycert.csr", $binCsr)

# Submit the CSR to the SCEPman REST API using az, which handles authentication
$null = az rest --method POST --uri "$ScepmanUrl/api/csr" --body '@mycert.csr' --headers "Content-Type=application/octet-stream" --output-file mycert.cer

# Extract the certificate from the response, merge it with the RSA key, and save as Pkcs12
$certificate = new-object System.Security.Cryptography.X509Certificates.X509Certificate2("mycert.cer")
$pkcs12 = new-object System.Security.Cryptography.Pkcs.Pkcs12Builder
$pkcs12CertContent = new-object System.Security.Cryptography.Pkcs.Pkcs12SafeContents
$null = $pkcs12CertContent.AddCertificate($certificate)
$passwordParameters = new-object System.Security.Cryptography.PbeParameters(
  [System.Security.Cryptography.PbeEncryptionAlgorithm]::Aes256Cbc,
  [System.Security.Cryptography.HashAlgorithmName]::SHA256,
  1000)
$null = $pkcs12CertContent.AddShroudedKey($rsakey, $password, $passwordParameters)
$null = $pkcs12.AddSafeContentsUnencrypted($pkcs12CertContent)
$pkcs12.SealWithMac($password, [System.Security.Cryptography.HashAlgorithmName]::SHA256, 1000)
$baPfx = $pkcs12.Encode()

# Save the Pkcs12 to disk
[System.IO.File]::WriteAllBytes("mycert.pfx", $baPfx)