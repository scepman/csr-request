#!/bin/bash

# $1 = the certificate's name
# $2 = SCEPman instance URL

# TODO: if revoked then do nothing

if sudo openssl x509 -checkend 864000 -noout -in $1; then
    # Certificate is not expiring in next 10 days - don't renew
else
    # Certificate will expire soon, renew using mTLS
    # Create a CSR
    openssl genrsa -des3 -out ipserver-cert.key 2048
    openssl req -new -key ipserver-cert.key -sha256 -out ipserver-cert.csr -config openssl-ipserver.config
    # Certificate is presumably PEM since all certificates in the Ubuntu certificate store are?
    # So convert the certificate to .crt so it can be renewed. Do I need to install openssl
    sudo cp /etc/ssl/certs/$1.pem $1.crt
    sudo cp /etc/ssl/private/$1.key $1.key
    # Create renewed version of certificate.
    echo "-----BEGIN PKCS7-----" > $1.p7b
    curl -X POST --data "@ipserver-cert.csr" -H "Content-Type: application/pkcs10" --cert $1.crt --key $1.key  --cacert /etc/ssl/certs/ca-certificates.crt $2/.well-known/est/simplereenroll >> $1.p7b
    printf "\n-----END PKCS7-----" >> $1.p7b
    # How to extract key from the renewed cert? Does the cert come out of the terminal
    openssl pkcs7 -print_certs -in $1.p7b -out /etc/ssl/certs/$1.pem
fi