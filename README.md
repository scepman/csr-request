# CSR REST Request Sample Code Library

Examples for using the [SCEPman REST API](https://docs.scepman.com/certificate-deployment/api-certificates) to request certificates.

Submissions are welcome!

## PowerShell and az

The PowerShell script [request-certificate-with-az.ps1](request-certificate-with-az.ps1) uses PowerShell to generate an RSA key, az to submit it to SCEPman's CSR endpoint with AAD authentication, and again .NET Core to merge the issued certificate with the RSA private key to a PFX file.

You need to call az login before running the script, so az can authenticate to the CSR endpoint.

## License

All code is available under the terms of the [MIT License](LICENSE).