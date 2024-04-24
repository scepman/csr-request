#!/bin/bash

# $1 = the name of the certificate being renewed
# $2 = SCEPman instance URL
# $3 = certificate directory
# $4 = key directory
# $5 = path to the root certificate (assuming it is pem encoded)

# Example command: 
# sh renewcertificate.sh my-certificate https://app-scepman-csz5hqanxf6cs.azurewebsites.net/ . .  /etc/ssl/scepman-dxun-root.pem



CERTNAME="$1"
APPSERVICE_URL="$2"
ABS_CERDIR=`readlink -f "$3"`
ABS_KEYDIR=`readlink -f "$4"`
ABS_ROOT=`readlink -f "$5"`

echo "I ran" >> "/mnt/c/Users/BenGodwin/OneDrive - glueckkanja-gab/Desktop/csr-request/enroll-certificate/file.txt" 

# TODO
# Check if issuing certificate is scepman root?
# Check entire chain of trust?

pwd

# if revoked then do nothing
OCSP_STATUS=`openssl ocsp -issuer "$ABS_ROOT" -cert "$ABS_CERDIR/$CERTNAME.pem" -url "$APPSERVICE_URL/ocsp"` 
TRIMMED_STATUS=`echo "$OCSP_STATUS" | grep "good"`
if ! [ -z "${TRIMMED_STATUS}" ]; then
    if ! openssl x509 -checkend 864000 -noout -in "$ABS_CERDIR/$CERTNAME.pem"; then
        # Certificate will expire within 10 days, renew using mTLS. 

        # Create a CSR
        openssl genrsa -out temporary.key 2048
        # I don't think the config is important apart from maybe the challenge password? ATM included in package.
        openssl req -new -key temporary.key -sha256 -out temporary.csr -config "/mnt/c/Users/BenGodwin/OneDrive - glueckkanja-gab/Desktop/csr-request/enroll-certificate/opensslconf.config" #fix this hard coding
        # Create renewed version of certificate.
        echo "-----BEGIN PKCS7-----" > "$CERTNAME.p7b"
        curl -X POST --data "@temporary.csr" -H "Content-Type: application/pkcs10" --cert "$ABS_CERDIR/$CERTNAME.pem" --key "$ABS_KEYDIR/$CERTNAME.key"  --cacert /etc/ssl/certs/ca-certificates.crt "$APPSERVICE_URL/.well-known/est/simplereenroll" >> "$CERTNAME.p7b"
        printf "\n-----END PKCS7-----" >> "$CERTNAME.p7b"
        openssl pkcs7 -print_certs -in "$CERTNAME.p7b" -out "$ABS_CERDIR/$CERTNAME.pem"
        cp temporary.key "$ABS_KEYDIR/$CERTNAME.key"
        # TODO? Remove old expired certificate? Remove temporary files?
    else 
        echo "certificate not expiring soon"
    fi
else
    echo "ocsp failed - probably invalid paths or revoked certificate" #can update this to reflect all of openssl ocsp errors
fi


