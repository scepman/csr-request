# CSR REST Request Sample Code Library

Examples for using the [SCEPman REST API](https://docs.scepman.com/certificate-deployment/api-certificates) to request certificates. All examples should be adapted to your environment before production usage.

Submissions are welcome!

## PowerShell and az

The PowerShell script [request-certificate-with-az.ps1](request-certificate-with-az.ps1) uses PowerShell to generate an RSA key, az to submit it to SCEPman's CSR endpoint with AAD authentication, and again .NET Core to merge the issued certificate with the RSA private key to a PFX file.

You need to call az login before running the script, so az can authenticate to the CSR endpoint.

## C# on .NET 7

The C# Console application [CsrClient](CsrClient) shows how to use the API with C#. It generates an ECC key pair and creates a CSR with the key. A JWT token is acquired using MSAL and that authenticates the request send to SCEPman's CSR REST API. The resulting certificate is combined with the key pair and saved as PFX file.

There are three options for authentication:

### 1. Default authentication

Usage: `CsrClient SCEPMAN_BASE_URL SCEPMAN_API_SCOPE`

If you pass only SCEPMAN_BASE_URL and SCEPMAN_API_SCOPE, you must have some "default" authentication at hand that allows you to submit requests to the CSR REST API. For example, if you are authenticated with az, the az credentials are used for the authentication.

### 2. Certificate-based authentication

Usage: `CsrClient SCEPMAN_BASE_URL SCEPMAN_API_SCOPE CLIENT_ID CERTIFICATE_SPECIFICATION TENANT_ID`

If you also pass CLIENT_ID andd TENANT_ID, this will authenticate as an Enterprise App. The Enterprise App must have the permission on your scepman-api Enterprise App (it must be added to the Role).

`CERTIFICATE_SPECIFICATION` can be either *cert-file:{path-to-pfx-file}* or *cert-store:{thumbprint}*. In the first case, the certificate is loaded from the specified PFX file. In the second case, the certificate is loaded from the local Personal certificate store of the current user. The certificate must have a private key. The certificate can be mapped from a smard-card to the store.

You may create a self-signed certificate with PowerShell with this command, for example:

`New-SelfSignedCertificate -Subject "CN=scepman-client-cert" -CertStoreLocation "Cert:\CurrentUser\My" -KeyExportPolicy NonExportable -KeySpec Signature -KeyLength 2048 -KeyAlgorithm RSA -HashAlgorithm SHA256 -NotAfter (Get-Date).AddYears(10)`

Afterwards, export the public part of the certificate and add it to your app registration as a certificate under the "Certificates & secrets" section.

### 3. Client secret authentication

Usage: `CsrClient SCEPMAN_BASE_URL SCEPMAN_API_SCOPE CLIENT_ID secret:{CLIENT_SECRET} TENANT_ID`

This option is similar to the previous one, but uses a client secret instead of a certificate. The client secret must be created in the "Certificates & secrets" section of your app registration.

## License

All code is available under the terms of the [MIT License](LICENSE).
