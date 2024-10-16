#!/bin/bash

# Arguments:
# $1 = SCEPman app service URL
# $2 = API scope of SCEPman-api app registration
# $3 = Desired name of certificate
# $4 = Directory where cert is to be installed
# $5 = Directory where key is to be installed
# $6 = Root certificate
# $7 = Device or User cert (not yet implemented)

# Example use:
# sh enrollcertificate.sh https://your-scepman-domain.azurewebsites.net/ api://123guid cert-name cert-directory key-directory root.pem

APPSERVICE_URL="$1"
API_SCOPE="$2"
CERTNAME="$3"
ABS_CERDIR=$(readlink -f "$4")
ABS_KEYDIR=$(readlink -f "$5")
ABS_ROOT=$(readlink -f "$6")
ABS_KEY="$ABS_KEYDIR/$CERTNAME.key"
ABS_CER="$ABS_CERDIR/$CERTNAME.pem"

TEMP=$(mktemp -d tmpXXXXXXX)
TEMP_CSR="csr.req"
TEMP_KEY="key.pem"
TEMP_P7B="file.p7b"
TEMP_PEM="cert.pem"

trap "rm -r $TEMP" EXIT

# Create a CSR
openssl genrsa -out "$TEMP_KEY" 4096
# Unsure if challenge password is necessary for CSR.
openssl req -new -key "$TEMP_KEY" -sha256 -out "$TEMP_CSR" -subj "/CN=vm-win11-3" -config "openssl-usercert-clientauth-example.config"

az login --scope "$API_SCOPE/.default" --allow-no-subscriptions
KV_TOKEN=$(az account get-access-token --scope "$API_SCOPE/.default" --query accessToken --output tsv)
KV_TOKEN=$(echo "$KV_TOKEN" | sed 's/[[:space:]]*$//') # Remove trailing whitespace

# Create certificate
echo "-----BEGIN PKCS7-----" > "$TEMP_P7B"
curl -X POST --data "@$TEMP_CSR" -H "Content-Type: application/pkcs10" -H "Authorization: Bearer $KV_TOKEN" --cacert "$ABS_ROOT" "$APPSERVICE_URL/.well-known/est/simpleenroll" >> "$TEMP_P7B"
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
