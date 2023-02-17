# CSR REST Request Sample Code Library

Examples for using the [SCEPman REST API](https://docs.scepman.com/certificate-deployment/api-certificates) to request certificates.

Submissions are welcome!

## PowerShell and az

The PowerShell script [request-certificate-with-az.ps1](request-certificate-with-az.ps1) uses PowerShell to generate an RSA key, az to submit it to SCEPman's CSR endpoint with AAD authentication, and again .NET Core to merge the issued certificate with the RSA private key to a PFX file.

You need to call az login before running the script, so az can authenticate to the CSR endpoint.

## C# on .NET 7

The C# Console application [CsrClient](CsrClient) shows how to use the API with C#. It generates an ECC key pair and creates a CSR with the key. A JWT token is acquired using MSAL and that authenticates the request send to SCEPman's CSR REST API. The resulting certificate is combined with the key pair and saved as PFX file.

Usage:
`CsrClient SCEPMAN_BASE_URL SCEPMAN_API_SCOPE [CLIENT_ID CLIENT_SECRET TENANT_ID]`

There are two options for authentication:

- If you pass only SCEPMAN_BASE_URL and SCEPMAN_API_SCOPE, you must have some "default" authentication at hand that allows you to submit requests to the CSR REST API. For example, if you are authenticated with az, the az credentials are used for the authentication.
- If you also pass CLIENT_ID, CLIENT_SECRET, and TENANT_ID, this will authenticate as an Enterprise App. The Enterprise App must have the permission on your scepman-api Enterprise App (it must be added to the Role).

## License

All code is available under the terms of the [MIT License](LICENSE).