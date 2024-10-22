#!/bin/bash

# Arguments:
# -d or -u depending on whether it is a device or user cerificate to be enrolled
# $1 = SCEPman app service URL
# $2 = API scope of SCEPman-api app registration
# $3 = Desired name of certificate
# $4 = Directory where cert is to be installed
# $5 = Directory where key is to be installed
# $6 = Root certificate
# $7 = Renewal threshold in days


# Example use:
# sh enrollcertificate.sh https://your-scepman-domain.azurewebsites.net/ api://123guid cert-name cert-directory key-directory root.pem

# Default certificate type
CERT_TYPE="user"

# # Parse command-line options
# while getopts ":u:d:" opt; do
#   case ${opt} in
#     u )
#       CERT_TYPE="user"
#       ;;
#     d )
#       CERT_TYPE="device"
#       ;;
#     \? )
#       echo "Usage: -u for user certificate, -d for device certificate" 1>&2
#       exit 1
#       ;;
#   esac
# done
# shift 1

APPSERVICE_URL="$1"
API_SCOPE="$2"
CERTNAME="$3"
ABS_CERDIR=$(readlink -f "$4")
ABS_KEYDIR=$(readlink -f "$5")
ABS_ROOT=$(readlink -f "$6")
RENEWAL_THRESHOLD_DAYS="$7"
ABS_KEY="$ABS_KEYDIR/$CERTNAME.key"
ABS_CER="$ABS_CERDIR/$CERTNAME.pem"

SECONDS_IN_DAY="86400"
if [[ -z "$RENEWAL_THRESHOLD_DAYS" ]]; then
    RENEWAL_THRESHOLD_DAYS="30"
fi
RENEWAL_THRESHOLD=$(($RENEWAL_THRESHOLD_DAYS * $SECONDS_IN_DAY))

TEMP=$(mktemp -d tmpXXXXXXX)
TEMP_CSR="$TEMP/tmp.csr"
TEMP_KEY="$TEMP/tmp.key"
TEMP_P7B="$TEMP/tmp.p7b"
TEMP_PEM="$TEMP/tmp.pem"

trap "rm -r $TEMP" EXIT

if [[ -e "$ABS_CER" ]]; then
    echo "Cert already exists in file: enacting renewal protocol"
    OCSP_STATUS=`openssl ocsp -issuer "$ABS_ROOT" -cert "$ABS_CER" -url "$APPSERVICE_URL/ocsp"`
    TRIMMED_STATUS=`echo "$OCSP_STATUS" | grep "good"`
    if [[ ! -e "$ABS_KEY" ]]; then
        echo "The certificate exists but no private key can be found, exiting"
        exit 1
    fi
    if [ -z "${TRIMMED_STATUS}" ]; then
        echo "OCSP failed - probably invalid paths or revoked certificate, exiting" #can update this to reflect all of openssl ocsp errors
        exit 1
    fi
    if openssl x509 -checkend $RENEWAL_THRESHOLD -noout -in "$ABS_CER"; then
        echo "Certificate not expiring within the threshold of $RENEWAL_THRESHOLD_DAYS days, exiting"
        exit 1
    fi
    SUBJECT="/CN=Contoso"
    CURL_CMD='curl -X POST --data "@$TEMP_CSR" -H "Content-Type: application/pkcs10" --cert "$ABS_CER" --key "$ABS_KEY" --cacert "$ABS_ROOT" "$APPSERVICE_URL/.well-known/est/simplereenroll"'
    EXTENSION1="subjectAltName=otherName:1.3.6.1.4.1.311.20.2.3;UTF8:$UPN" # remove this
else
    echo "Cert does not exist in file: enacting enrollment protocol"
    if [[ $CERT_TYPE == "user" ]];
    then
        USER_OBJECT=$(az ad signed-in-user show)
        UPN=$(echo "$USER_OBJECT" | grep -oP '"mail": *"\K[^"]*')
        SUBJECT="/CN=$UPN"
        EXTENSION1="subjectAltName=otherName:1.3.6.1.4.1.311.20.2.3;UTF8:$UPN"

    else
        echo "DEVICE CERTIFICATE NOT YET IMPLEMENTED"
        DEVICE_ID=$(az rest --method get --uri "https://graph.microsoft.com/v1.0/me/managedDevices" --query "value[0].id" -o tsv)
        SUBJECT="/CN=$DEVICE_ID"
        EXTENSION1="subjectAltName=URI:IntuneDeviceId://{whatever the device ID is, not yet implemented}"
    fi

    az login --scope "$API_SCOPE/.default" --allow-no-subscriptions
    KV_TOKEN=$(az account get-access-token --scope "$API_SCOPE/.default" --query accessToken --output tsv)
    KV_TOKEN=$(echo "$KV_TOKEN" | sed 's/[[:space:]]*$//') # Remove trailing whitespace

    CURL_CMD='curl -X POST --data "@$TEMP_CSR" -H "Content-Type: application/pkcs10" -H "Authorization: Bearer $KV_TOKEN" --cacert "$ABS_ROOT" "$APPSERVICE_URL/.well-known/est/simpleenroll" >> "$TEMP_P7B"'
fi

EXTENSION2="extendedKeyUsage=1.3.6.1.5.5.7.3.2"

# Create a CSR
openssl genrsa -out "$TEMP_KEY" 4096
openssl req -new -key "$TEMP_KEY" -sha256 -out "$TEMP_CSR" -subj "$SUBJECT" -addext "$EXTENSION1" -addext "$EXTENSION2"

# Create certificate
echo "-----BEGIN PKCS7-----" > "$TEMP_P7B"
eval $CURL_CMD >> "$TEMP_P7B"
printf "\n-----END PKCS7-----" >> "$TEMP_P7B"
openssl pkcs7 -print_certs -in "$TEMP_P7B" -out "$TEMP_PEM"
if [ -f $TEMP_PEM ]; then
    # only execute if new pem file created:
    cp "$TEMP_KEY" "$ABS_KEY"
    cp "$TEMP_PEM" "$ABS_CER"
else
    echo "API endpoint returned an error"
    exit 1
fi

# ABS_SCRIPTDIR="$HOME/.local/bin/cron/renewcertificate"
# mkdir -p "$ABS_SCRIPTDIR"
# cd ..
# cp renewcertificate.sh "$ABS_SCRIPTDIR/renewcertificate.sh"
# (crontab -l ; echo @daily "\"$ABS_SCRIPTDIR/renewcertificate.sh\"" "\"$APPSERVICE_URL\"" "\"$ABS_CERDIR/$CERTNAME.pem\"" "\"$ABS_KEYDIR/$CERTNAME.key\"" "\"$ABS_ROOT\"" "10") | crontab -
# (crontab -l ; echo @reboot "\"$ABS_SCRIPTDIR/renewcertificate.sh\"" "\"$APPSERVICE_URL\"" "\"$ABS_CERDIR/$CERTNAME.pem\"" "\"$ABS_KEYDIR/$CERTNAME.key\"" "\"$ABS_ROOT\"" "10") | crontab -
