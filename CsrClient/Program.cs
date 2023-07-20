// 2023 (c) glueckkanja-gab AG
// Available under the terms of the MIT License, see LICENSE

using Azure.Core;
using Azure.Identity;
using CsrClient;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;

Command command = Enum.Parse<Command>(args[0], true);
string scepmanBaseUrl = args[1];    // Example: https://scepman.example.com

AccessToken accessToken;
X509Certificate2 clientAuthenticationCertificate = null;
if (command == Command.csr || command == Command.est)
{
    string scepmanApiScope = args[2];   // Example: api://14a287e1-2ccd-4633-8747-4e97c002d06d  (Look up the correct GUID from your app registration scepman-api)

    if (args.Length > 3)
    {
        string clientId = args[3];
        string tenantId = args[5];

        string authenticationMethod = args[4];

        if (authenticationMethod.StartsWith("secret:")) // Authenticate with Client Secret
        {
            string clientSecret = authenticationMethod["secret:".Length..];
            ClientSecretCredential accessCredential = new(tenantId, clientId, clientSecret);
            accessToken = await accessCredential.GetTokenAsync(new TokenRequestContext(new[] { $"{scepmanApiScope}/.default" }));
        }
        else if (authenticationMethod.StartsWith("cert"))   // Authenticate with Client Certificate (usually self-signed)
        {
            clientAuthenticationCertificate = ProvideAuthenticationCertificate(args.Length > 6 ? args[6] : null, authenticationMethod);

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

}
else if (command == Command.reenroll)
{
    accessToken = new();    // not needed for EST ReEnrollment
    clientAuthenticationCertificate = ProvideAuthenticationCertificate(args.Length > 3 ? args[3] : null, args[2]);
}
else
    throw new NotSupportedException();

// Create certificate request
ECDsa key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
CertificateRequest request = new(
    new X500DistinguishedName("CN=Test"),
    key,
    HashAlgorithmName.SHA256
);
OidCollection ekus = new();
ekus.Add(new Oid("1.3.6.1.5.5.7.3.2"));  // Client Authentication
request.CertificateExtensions.Add(new X509EnhancedKeyUsageExtension(ekus, true));
byte[] baCsr = request.CreateSigningRequest();


// Send request to SCEPMan to issue the certificate
CsrCaClient client = new(
    scepmanBaseUrl,
    accessToken
);
byte[] certificate = command switch
{
    Command.csr => await client.IssueCertificateOverCsrApi(baCsr),
    Command.est => await client.IssueCertificateOverEst(baCsr),
    Command.reenroll => await client.ReenrollCertificate(baCsr, clientAuthenticationCertificate!),
    _ => throw new NotSupportedException()
};

// Merge certificate and private key to store as PKCS#12
X509Certificate2 cert = new(certificate);
cert = cert.CopyWithPrivateKey(key);
byte[] baPfx = cert.Export(X509ContentType.Pkcs12, "password");
File.WriteAllBytes("my-certificate.pfx", baPfx);

static X509Certificate2 ProvideAuthenticationCertificate(string? certificatePassword, string authenticationMethod)
{
    if (authenticationMethod.StartsWith("cert-file:"))  // Read certificate from a PFX file
    {
        string certificatePath = authenticationMethod["cert-file:".Length..];
        return new X509Certificate2(certificatePath, certificatePassword);
    }
    else if (authenticationMethod.StartsWith("cert-store:")) // Use certificate stored in the user's MY store
    {
        string certificateThumbprint = authenticationMethod["cert-store:".Length..];

        X509Store myStore = new(StoreName.My, StoreLocation.CurrentUser);
        myStore.Open(OpenFlags.ReadOnly);
        return myStore.Certificates.Single(cert => cert.Thumbprint.Equals(certificateThumbprint, StringComparison.InvariantCultureIgnoreCase));
    }
    else
    {
        throw new ArgumentException("Invalid authentication method");
    }
}