// 2023 (c) glueckkanja-gab AG
// Available under the terms of the MIT License, see LICENSE

using Azure.Core;
using Azure.Identity;
using CsrClient;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;

string scepmanBaseUrl = args[0];    // Example: https://scepman.example.com
string scepmanApiScope = args[1];   // Example: api://14a287e1-2ccd-4633-8747-4e97c002d06d  (Look up the correct GUID from your app registration scepman-api)

AccessToken accessToken;
if (args.Length > 2)
{
    string clientId = args[2];
    string tenantId = args[4];

    string authenticationMethod = args[3];

    if (authenticationMethod.StartsWith("secret:")) // Authenticate with Client Secret
    {
        string clientSecret = authenticationMethod["secret:".Length..];
        ClientSecretCredential accessCredential = new(tenantId, clientId, clientSecret);
        accessToken = await accessCredential.GetTokenAsync(new TokenRequestContext(new[] { $"{scepmanApiScope}/.default" }));
    }
    else if (authenticationMethod.StartsWith("cert"))   // Authenticate with Client Certificate (usually self-signed)
    {
        X509Certificate2 clientAuthenticationCertificate;
        if (authenticationMethod.StartsWith("cert-file:"))  // Read certificate from a PFX file
        {
            string certificatePath = authenticationMethod["cert-file:".Length..];
            string certificatePassword = args[5];
            clientAuthenticationCertificate = new(certificatePath, certificatePassword);
        }
        else if (authenticationMethod.StartsWith("cert-store:")) // Use certificate stored in the user's MY store
        {
            string certificateThumbprint = authenticationMethod["cert-store:".Length..];

            X509Store myStore = new(StoreName.My, StoreLocation.CurrentUser);
            myStore.Open(OpenFlags.ReadOnly);
            clientAuthenticationCertificate = myStore.Certificates.Single(cert => cert.Thumbprint.Equals(certificateThumbprint, StringComparison.InvariantCultureIgnoreCase));
        }
        else
        {
            throw new ArgumentException("Invalid authentication method");
        }

        ClientCertificateCredential accessCredential = new(tenantId, clientId, clientAuthenticationCertificate);
        accessToken = await accessCredential.GetTokenAsync(new TokenRequestContext(new[] { $"{scepmanApiScope}/.default" }));
    }
    else
    {
        throw new ArgumentException("Invalid authentication method");
    }
}
else
{
    DefaultAzureCredential accessCredential = new(); // Tries all kinds of available credentials, see https://docs.microsoft.com/en-us/dotnet/api/azure.identity.defaultazurecredential?view=azure-dotnet
    accessToken = await accessCredential.GetTokenAsync(new TokenRequestContext(new[] { scepmanApiScope }));
}


// Create certificate request
ECDsa key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
CertificateRequest request = new(
    new X500DistinguishedName("CN=Test"),
    key,
    HashAlgorithmName.SHA256
);
byte[] baCsr = request.CreateSigningRequest();


// Send request to SCEPMan to issue the certificate
CsrCaClient client = new(
    scepmanBaseUrl,
    accessToken
);
byte[] certificate = await client.IssueCertificate(baCsr);

// Merge certificate and private key to store as PKCS#12
X509Certificate2 cert = new(certificate);
cert = cert.CopyWithPrivateKey(key);
byte[] baPfx = cert.Export(X509ContentType.Pkcs12, "password");
File.WriteAllBytes("my-certificate.pfx", baPfx);