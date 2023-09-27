<# 
request-certificate-with-az.ps1 Version: 20230216
C. Hannebauer - glueckkanja-gab

  .DESCRIPTION
    Uses .NET to generate an RSA key, az to submit it to SCEPman's CSR endpoint with AAD authentication, and again .NET Core to merge the issued certificate with the RSA private key to a PFX file.
    The script creates some files in the working directory.
    This script serves as an example for how to use the SCEPman REST API to request certificates. It is not intended to be used in production.

  .PARAMETER ScepmanUrl
    Url of SCEPman without trailing slash, e.g. https://your-scepman.azurewebsites.net

  .PARAMETER ScepmanApiScope
    The scope of the API, which by default has the form api://<api-id>. You can copy the value from your Certificate Master's SCEPmanAPIScope setting (see https://docs.scepman.com/advanced-configuration/application-settings-1/azure-ad#appconfig-authconfig-scepmanapiscope)

  .PARAMETER CertificateSubject
    The subject of the certificate to be created, e.g. CN=MyCert

  .PARAMETER Password
    The password for the PFX file that will be created

  .EXAMPLE
    .\request-certificate-with-az.ps1 -ScepmanUrl https://your-scepman.azurewebsites.net -CertificateSubject "CN=MyCert" -Password "password"

  .NOTES
    Available under the MIT license. See LICENSE file for details.

    You may need to call az login before running this script and log in as a service principal or Managed Identity (https://learn.microsoft.com/en-us/cli/azure/authenticate-azure-cli?view=azure-cli-latest#sign-in-with-a-service-principal)
    Alternatively, you may modify the scepman-api app registration to allow users for the App role CSR.Request.Db, and additionally, 
    add az (04b07795-8ddb-461a-bbee-02f9e1bf7b46) as authorized client application to your Azure AD app registration 'scepman-api'.
    This alternative allows users to request certificates.

#>
[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)][string]$ScepmanUrl,
    [Parameter(Mandatory=$true)][string]$ScepmanApiScope,
    [string]$certificateSubject = "CN=MyCert",
    [string]$password = "password"
)

# Create a new RSA key pair and certificate request using .NET
$rsakey = [System.Security.Cryptography.RSA]::Create()
$csr = new-object System.Security.Cryptography.X509Certificates.CertificateRequest(
  $certificateSubject, $rsakey, 
  [System.Security.Cryptography.HashAlgorithmName]::SHA256, 
  [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
$binCsr = $csr.CreateSigningRequest()
$csrPath = Join-Path (Get-Location) "mycert.csr"
[System.IO.File]::WriteAllBytes($csrPath, $binCsr)

# Submit the CSR to the SCEPman REST API using az, which handles authentication
$null = az rest --method POST --uri "$ScepmanUrl/api/csr" --body '@mycert.csr' --headers "Content-Type=application/octet-stream" --output-file mycert.cer --resource $ScepmanApiScope

# Extract the certificate from the response, merge it with the RSA key, and save as Pkcs12
$certPath = Join-Path (Get-Location) "mycert.cer"
$certificate = new-object System.Security.Cryptography.X509Certificates.X509Certificate2($certPath)
$pkcs12 = new-object System.Security.Cryptography.Pkcs.Pkcs12Builder
$pkcs12CertContent = new-object System.Security.Cryptography.Pkcs.Pkcs12SafeContents
$null = $pkcs12CertContent.AddCertificate($certificate)
$passwordParameters = new-object System.Security.Cryptography.PbeParameters(
  [System.Security.Cryptography.PbeEncryptionAlgorithm]::Aes256Cbc,
  [System.Security.Cryptography.HashAlgorithmName]::SHA256,
  1000)
$null = $pkcs12CertContent.AddShroudedKey($rsakey, $password, $passwordParameters)
$null = $pkcs12.AddSafeContentsUnencrypted($pkcs12CertContent)
$pkcs12.SealWithMac($password, [System.Security.Cryptography.HashAlgorithmName]::SHA1, 2000)
$baPfx = $pkcs12.Encode()

# Save the Pkcs12 to disk
$pfxPath = Join-Path (Get-Location) "mycert.pfx"
[System.IO.File]::WriteAllBytes($pfxPath, $baPfx)