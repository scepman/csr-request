#!/bin/bash

# $1 = the certificate's name
# $2 = SCEPman instance URL
# $3 = the path to the certificate
# $4 = the path to the key

# Example command: 
# sh renewcertificate.sh my-certificate https://app-scepman-csz5hqanxf6cs.azurewebsites.net/ csrclient csrclient

# if revoked then do nothing
# May be working? have to check with expired cert
if openssl ocsp -text -issuer /etc/ssl/certs/ca-certificates.crt -cert $3/$1.pem -text -url http://app-scepman-csz5hqanxf6cs.azurewebsites.net/ocsp; then
    # do nothing
    echo "ocsp not expired"
else
    echo "ocsp expired"
fi


if openssl x509 -checkend 864000 -noout -in $3/$1; then
    # Certificate is not expiring in next 10 days - don't renew
else
    # Certificate will expire soon, renew using mTLS. Seems to work after testing.
    # Create a CSR
    openssl genrsa -des3 -out temporary.key 2048
    # I don't think the config is important apart from maybe the challenge password? 
    openssl req -new -key temporary.key -sha256 -out temporary.csr -config openssl-ipserver.config
    # Create renewed version of certificate.
    echo "-----BEGIN PKCS7-----" > $1.p7b
    curl -X POST --data "@temporary.csr" -H "Content-Type: application/pkcs10" --cert $3/$1.pem --key $4/$1.key  --cacert /etc/ssl/certs/ca-certificates.crt $2/.well-known/est/simplereenroll >> $1.p7b
    printf "\n-----END PKCS7-----" >> $1.p7b
    openssl pkcs7 -print_certs -in $1.p7b -out $3/$1.pem
    cp temporary.key $4/$1.key
    # TODO? Remove old expired certificate? Remove temporary files?
fi