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
    string clientSecret = args[3];
    string tenantId = args[4];
    ClientSecretCredential accessCredential = new(tenantId, clientId, clientSecret);
    accessToken = await accessCredential.GetTokenAsync(new TokenRequestContext(new[] { $"{scepmanApiScope}/.default" }));

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