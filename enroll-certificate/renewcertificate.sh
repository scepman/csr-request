#!/bin/bash

# $1 = SCEPman instance URL
# $2 = certificate
# $3 = key 
# $4 = root certificate (PEM encoded)
# $5 = renewal threshold: 

# Example command: 
# sh renewcertificate.sh https://your-scepman-domain.net/ cert.pem cert.key root.pem openssl-conf.config 10


APPSERVICE_URL="$1"
ABS_CER=`readlink -f "$2"`
ABS_KEY=`readlink -f "$3"`
ABS_ROOT=`readlink -f "$4"`

TEMP=$(mktemp -d tmpXXXXXXX)
TEMP_CSR="$TEMP/tmp.csr"
TEMP_KEY="$TEMP/tmp.key"
TEMP_P7B="$TEMP/tmp.p7b"
TEMP_PEM="$TEMP/tmp.pem"

SECONDS_IN_DAY="86400"
RENEWAL_THRESHOLD_DAYS="$6" # Can be changed - number of days before expiry that a certificate will be renewed
RENEWAL_THRESHOLD=$(($RENEWAL_THRESHOLD_DAYS * $SECONDS_IN_DAY))

trap "rm -r $TEMP" EXIT

# if revoked then do nothing
OCSP_STATUS=`openssl ocsp -issuer "$ABS_ROOT" -cert "$ABS_CER" -url "$APPSERVICE_URL/ocsp"` 
TRIMMED_STATUS=`echo "$OCSP_STATUS" | grep "good"`
if ! [ -z "${TRIMMED_STATUS}" ]; then
    if ! openssl x509 -checkend $RENEWAL_THRESHOLD -noout -in "$ABS_CER"; then
        # Certificate will expire within 10 days, renew using mTLS. 
        
        # Create a CSR
        openssl genrsa -out "$TEMP_KEY"  4096
        # I don't think the config is important apart from maybe the challenge password? ATM included in package.
        openssl req -new -key "$TEMP_KEY" -sha256 -out "$TEMP_CSR" -subj "/C=US/ST=State/L=Locality/O=Contoso/OU=Unit/CN=Contoso/emailAddress=email@contoso.com"
        # Create renewed version of certificate.
        echo "-----BEGIN PKCS7-----" > "$TEMP_P7B"
        curl -X POST --data "@$TEMP_CSR" -H "Content-Type: application/pkcs10" --cert "$ABS_CER" --key "$ABS_KEY" --cacert "$ABS_ROOT" "$APPSERVICE_URL/.well-known/est/simplereenroll" >> "$TEMP_P7B"
        printf "\n-----END PKCS7-----" >> "$TEMP_P7B"
        openssl pkcs7 -print_certs -in "$TEMP_P7B" -out "$TEMP_PEM"
        if [ -f $TEMP_PEM ]; then
            # only execute if new pem file created:
            cp "$TEMP_KEY" "$ABS_KEY"
            cp "$TEMP_PEM" "$ABS_CER"
        else
            echo "Renewal endpoint returned an error"
            exit 1
        fi
        
    else 
        echo "Certificate not expiring soon"
        exit 1
    fi
else
    echo "OCSP failed - probably invalid paths or revoked certificate" #can update this to reflect all of openssl ocsp errors
    exit 1
fi

