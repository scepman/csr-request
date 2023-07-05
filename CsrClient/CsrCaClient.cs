using Azure.Core;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Security.Cryptography.Pkcs;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Threading.Tasks;

namespace CsrClient
{
    public class CsrCaClient
    {
        public string Url { get; set; }

        private HttpClient client = new();
        private readonly AccessToken token;

        public string CSREndpointURL
        {
            get
            {
                string url = Url.TrimEnd('/');
                if (!url.EndsWith("/api/csr"))
                    url += "/api/csr";
                return url + '/';
            }
        }

        public string EstEndpointURL => Url.TrimEnd('/') + "/.well-known/est/";

        public CsrCaClient(string url, AccessToken token)
        {
            Url = url;
            this.token = token;
        }

        public Task<byte[]> IssueCertificateOverCsrApi(byte[] request) => IssueCertificate(request, CSREndpointURL, null);
        public Task<byte[]> IssueCertificateOverEst(byte[] request) => IssueCertificate(request, EstEndpointURL + "simpleenroll", null);
        public Task<byte[]> ReenrollCertificate(byte[] request, X509Certificate2 clientAuthenticationCertificate) => IssueCertificate(request, EstEndpointURL + "simplereenroll", clientAuthenticationCertificate);

        private async Task<byte[]> IssueCertificate(byte[] request, string endpointUrl, X509Certificate2? clientAuthenticationCertificate)
        {
            HttpClient httpClient = client;
            if (null != clientAuthenticationCertificate)
            {
                HttpClientHandler hch = new();
                hch.ClientCertificates.Add(clientAuthenticationCertificate);
                httpClient = new HttpClient(hch);
            }
            else
                httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token.Token);
            ByteArrayContent requestContent = new(request);
            //requestContent.Headers.ContentType = new MediaTypeHeaderValue("application/pkcs10");
            HttpResponseMessage response = await httpClient.PostAsync(endpointUrl, requestContent);

            if (response.IsSuccessStatusCode)
            {
                return response.Content switch
                {
                    { Headers.ContentType.MediaType: "application/pkix-cert" } => await response.Content.ReadAsByteArrayAsync(),
                    { Headers.ContentType.MediaType: "application/pkcs7-mime" } => ParseCertificateFromPkcs7(await response.Content.ReadAsByteArrayAsync()),
                    _ => throw new NotSupportedException($"Unsupported media type {response.Content.Headers.ContentType?.MediaType}")
                }; ;
            }
            else
                throw new HttpRequestException($"Could not issue certificate on backend, HTTP Status Code was {response.StatusCode} with reason {response.ReasonPhrase}", null, response.StatusCode);
        }

        private byte[] ParseCertificateFromPkcs7(byte[] bytes)
        {
            if (bytes[0] == (byte)'M')  // Base64 encoded?
                bytes = Convert.FromBase64String(Encoding.ASCII.GetString(bytes));

            SignedCms cms = new();
            cms.Decode(bytes);
            X509Certificate2 issuedCertificate = cms.Certificates.Single(cert => !IsCaCertificate(cert));

            return issuedCertificate.Export(X509ContentType.Cert);
        }

        private bool IsCaCertificate(X509Certificate2 cert)
        {
            var extBcCandidate = cert.Extensions
                .SingleOrDefault(ext => ext is X509BasicConstraintsExtension);

            if (extBcCandidate is not X509BasicConstraintsExtension extBc)
                return false;

            return extBc.CertificateAuthority;
        }
    }
}
