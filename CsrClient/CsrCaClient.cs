using Azure.Core;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http.Headers;
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
                if (!url.EndsWith("/csr"))
                    url += "/csr";
                return url + '/';
            }
        }

        public CsrCaClient(string url, AccessToken token)
        {
            Url = url;
            this.token = token;
        }

        public async Task<byte[]> IssueCertificate(byte[] request)
        {
            client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token.Token);
            ByteArrayContent requestContent = new(request);
            //requestContent.Headers.ContentType = new MediaTypeHeaderValue("application/pkcs10");
            HttpResponseMessage response = await client.PostAsync(CSREndpointURL, requestContent);

            if (response.IsSuccessStatusCode)
                return await response.Content.ReadAsByteArrayAsync();
            else
                throw new HttpRequestException($"Could not issue certificate on backend, HTTP Status Code was {response.StatusCode} with reason {response.ReasonPhrase}", null, response.StatusCode);
        }

    }
}
