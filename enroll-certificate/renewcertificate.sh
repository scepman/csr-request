#!/bin/bash

# $1 = the certificate's name
# $2 = SCEPman instance URL
# $3 = the path to the certificate
# $4 = the path to the key

# TODO: if revoked then do nothing

if sudo openssl x509 -checkend 864000 -noout -in $3/$1; then
    # Certificate is not expiring in next 10 days - don't renew
else
    # Certificate will expire soon, renew using mTLS
    # Create a CSR
    openssl genrsa -des3 -out temporary.key 2048
    # I don't think the config is important apart from maybe the challenge password? 
    openssl req -new -key temporary.key -sha256 -out temporary.csr -config openssl-ipserver.config
    # Create renewed version of certificate.
    echo "-----BEGIN PKCS7-----" > $1.p7b
    curl -X POST --data "@temporary.csr" -H "Content-Type: application/pkcs10" --cert $3/$1.crt --key $4/$1.key  --cacert /etc/ssl/certs/ca-certificates.crt $2/.well-known/est/simplereenroll >> $1.p7b
    printf "\n-----END PKCS7-----" >> $1.p7b
    # How to extract key from the renewed cert? Does the cert come out of the terminal
    openssl pkcs7 -print_certs -in $1.p7b -out $3/$1.pem
    cp temporary.key $4/$1.key
    # TODO? Remove old expired certificate?
fi