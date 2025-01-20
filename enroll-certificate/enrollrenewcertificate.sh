#!/bin/bash

# Version: 2024-12-16

# Commands (not yet implemented):
# -u for user certificate with auto-detection whether it is an initial enrollment or renewal
# -d for device certificate with auto-detection whether it is an initial enrollment or renewal
# -r for renewal
# -w for initial enrollment of a user
# -x for initial enrollment of a device

# Arguments:
# $1 = SCEPman app service URL
# $2 = API scope of SCEPman-api app registration
# $3 = Desired name of certificate
# $4 = Directory where cert is to be installed
# $5 = Directory where key is to be installed
# $6 = Root certificate
# $7 = Renewal threshold in days


# Example use:
# sh enrollcertificate.sh -u https://your-scepman-domain.azurewebsites.net/ api://123guid cert-name cert-directory key-directory root.pem

# Default certificate type and command
CERT_TYPE="user"
CERT_COMMAND="auto"

# Parse command-line options
while getopts ":udrwx" opt; do
  case ${opt} in
    u )
      CERT_TYPE="user"
      CERT_COMMAND="auto"
      ;;
    d )
      CERT_TYPE="device"
      CERT_COMMAND="auto"
      ;;
    r )
      CERT_COMMAND="renewal"
      ;;
    w )
      CERT_TYPE="user"
      CERT_COMMAND="initial"
      ;;
    x )
      CERT_TYPE="device"
      CERT_COMMAND="initial"
      ;;
    \? )
      echo "Usage: -u for user certificate, -d for device certificate, -r for renewal, -w for initial enrollment of a user, -x for initial enrollment of a device" 1>&2
      exit 1
      ;;
  esac
done
shift $((OPTIND -1))

APPSERVICE_URL="$1"
API_SCOPE="$2"
CERTNAME="$3"
ABS_CERDIR=$(readlink -f "$4")
ABS_KEYDIR=$(readlink -f "$5")
ABS_ROOT=$(readlink -f "$6")
RENEWAL_THRESHOLD_DAYS="$7"

# Define the log level (DEBUG, INFO, ERROR), defaulting to INFO
LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_FILE="${0##*/}.$(date '+%Y-%m-%d').log"

# Logging functions
log() {
	LEVEL=$1
	MESSAGE=$2

    if [ "$LEVEL" != "DEBUG" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [$LEVEL] $MESSAGE" | tee -a "$LOG_FILE"
    fi

    if [ "$LEVEL" == "DEBUG" ] && [ "$LOG_LEVEL" == "DEBUG" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [$LEVEL] $MESSAGE" | tee -a "$LOG_FILE"
    fi
}


log debug "Starting the certificate enrollment/renewal script"

log debug "CERT_TYPE: $CERT_TYPE; CERT_COMMAND: $CERT_COMMAND"

ABS_KEY="$ABS_KEYDIR/$CERTNAME.key"
ABS_CER="$ABS_CERDIR/$CERTNAME.pem"

log debug "APPSERVICE_URL: $APPSERVICE_URL"
log debug "API_SCOPE: $API_SCOPE"
log debug "CERTNAME: $CERTNAME"
log debug "ABS_CERDIR: $ABS_CERDIR"
log debug "ABS_KEYDIR: $ABS_KEYDIR"
log debug "RENEWAL_THRESHOLD_DAYS: $RENEWAL_THRESHOLD_DAYS"
log debug "ABS_KEY: $ABS_KEY"
log debug "ABS_CER: $ABS_CER"

SECONDS_IN_DAY="86400"
if [[ -z "$RENEWAL_THRESHOLD_DAYS" ]]; then
    RENEWAL_THRESHOLD_DAYS="30"
fi
RENEWAL_THRESHOLD=$(($RENEWAL_THRESHOLD_DAYS * $SECONDS_IN_DAY))

log debug "RENEWAL_THRESHOLD: $RENEWAL_THRESHOLD"

TEMP=$(mktemp -d tmpXXXXXXX)
TEMP_CSR="$TEMP/tmp.csr"
TEMP_KEY="$TEMP/tmp.key"
TEMP_P7B="$TEMP/tmp.p7b"
TEMP_PEM="$TEMP/tmp.pem"

log debug "Temporary directory created: $TEMP"

trap "rm -r $TEMP" EXIT

if [[ -e "$ABS_CER" ]]; then
    log info "Cert already exists in file $ABC_CER: enacting renewal protocol"
    OCSP_STATUS=$(openssl ocsp -issuer "$ABS_ROOT" -cert "$ABS_CER" -url "$APPSERVICE_URL/ocsp")
    TRIMMED_STATUS=$(echo "$OCSP_STATUS" | grep "good")
    log debug "OCSP_STATUS: $OCSP_STATUS"
    log debug "TRIMMED_STATUS: $TRIMMED_STATUS"
    if [[ ! -e "$ABS_KEY" ]]; then
        log error "The certificate exists but no private key can be found, exiting"
        exit 1
    fi
    if [ -z "${TRIMMED_STATUS}" ]; then
        log error "OCSP failed - probably invalid paths or revoked certificate, exiting"
        exit 1
    fi
    if openssl x509 -checkend $RENEWAL_THRESHOLD -noout -in "$ABS_CER"; then
        log info "Certificate not expiring within the threshold of $RENEWAL_THRESHOLD_DAYS days, exiting"
        exit 1
    fi
    SUBJECT="/CN=Contoso"
    CURL_CMD='curl -X POST --data "@$TEMP_CSR" -H "Content-Type: application/pkcs10" --cert "$ABS_CER" --key "$ABS_KEY" "$APPSERVICE_URL/.well-known/est/simplereenroll"'
    EXTENSION1="subjectAltName=otherName:1.3.6.1.4.1.311.20.2.3;UTF8:$UPN" # remove this
else
    log info "Cert does not exist in file $ABC_CER: enacting enrollment protocol"

    if ! command -v az &> /dev/null; then
        log error "Azure CLI (az) is not installed. Please install it and try again."
        exit 1
    else
        log debug "Azure CLI (az) is installed."
    fi

    if [[ $CERT_TYPE == "user" ]]; then
        log debug "CERT_TYPE is user"
        USER_OBJECT=$(az ad signed-in-user show)
        UPN=$(echo "$USER_OBJECT" | grep -oP '"mail": *"\K[^"]*')
        log debug "USER_OBJECT: $USER_OBJECT"
        log debug "UPN: $UPN"
        if [[ -z "$UPN" ]]; then
            log error "No UPN found, exiting"
            exit 1
        fi
        SUBJECT="/CN=$UPN"
        EXTENSION1="subjectAltName=otherName:1.3.6.1.4.1.311.20.2.3;UTF8:$UPN"

    else
        log debug "CERT_TYPE is device"
        
        REGISTRATION_FILE=~/.config/intune/registration.toml
        if [[ ! -f $REGISTRATION_FILE ]]; then
            log error "Intune registration.toml could not be found in $REGISTRATION_FILE"
            exit 1
        fi

        DEVICE_ID=$(cat $REGISTRATION_FILE | grep -oP '^device_hint = "\K[^"]*')
        AAD_DEVICE_ID=$(cat $REGISTRATION_FILE | grep -oP '^aad_device_hint = "\K[^"]*')

        # Check if DeviceId could be found in registration file
        if [[ ! -z "${DEVICE_ID}" ]]; then
            log debug "Found Intune DeviceId"

            SUBJECT="/CN=$DEVICE_ID"
            EXTENSION1="subjectAltName=URI:IntuneDeviceId://$DEVICE_ID"
        else
            if [[ -z "${AAD_DEVICE_ID}" ]]; then
                log error "Neither Intune DeviceId nor Entra DeviceId could be found"
                exit 1
            fi

            log debug "Intune DeviceId could not be found"
            log debug "Entra DeviceId will be used"

            SUBJECT="/CN=$AAD_DEVICE_ID"
        fi
    fi

    az login --scope "$API_SCOPE/.default" --allow-no-subscriptions
    KV_TOKEN=$(az account get-access-token --scope "$API_SCOPE/.default" --query accessToken --output tsv)
    KV_TOKEN=$(echo "$KV_TOKEN" | sed 's/[[:space:]]*$//') # Remove trailing whitespace

    if [[ -z "$KV_TOKEN" ]]; then
        log error "No token could be acquired, exiting"
        exit 1
    fi

    CURL_CMD='curl -X POST --data "@$TEMP_CSR" -H "Content-Type: application/pkcs10" -H "Authorization: Bearer $KV_TOKEN" "$APPSERVICE_URL/.well-known/est/simpleenroll" >> "$TEMP_P7B"'
fi

EXTENSION2="extendedKeyUsage=1.3.6.1.5.5.7.3.2"

# Create a CSR
log debug "Generating RSA key"
openssl genrsa -out "$TEMP_KEY" 4096
log debug "Generating CSR"
openssl req -new -key "$TEMP_KEY" -sha256 -out "$TEMP_CSR" -subj "$SUBJECT" -addext "$EXTENSION1" -addext "$EXTENSION2"

# Create certificate
log debug "Creating certificate"
echo "-----BEGIN PKCS7-----" > "$TEMP_P7B"
eval $CURL_CMD >> "$TEMP_P7B"
printf "\n-----END PKCS7-----" >> "$TEMP_P7B"
log debug "Converting PKCS7 to PEM"
openssl pkcs7 -print_certs -in "$TEMP_P7B" -out "$TEMP_PEM"
if [ -f $TEMP_PEM ]; then
    log debug "New PEM file created, copying key and certificate to $ABS_KEY and $ABS_CER, respectively"
    # only execute if new pem file created:
    cp "$TEMP_KEY" "$ABS_KEY"
    cp "$TEMP_PEM" "$ABS_CER"
    log info "Certificate successfully enrolled/renewed"
else
    log error "API endpoint returned an error"
    exit 1
fi

# ABS_SCRIPTDIR="$HOME/.local/bin/cron/renewcertificate"
# mkdir -p "$ABS_SCRIPTDIR"
# cd ..
# cp renewcertificate.sh "$ABS_SCRIPTDIR/renewcertificate.sh"
# (crontab -l ; echo @daily "\"$ABS_SCRIPTDIR/renewcertificate.sh\"" "\"$APPSERVICE_URL\"" "\"$ABS_CERDIR/$CERTNAME.pem\"" "\"$ABS_KEYDIR/$CERTNAME.key\"" "\"$ABS_ROOT\"" "10") | crontab -
# (crontab -l ; echo @reboot "\"$ABS_SCRIPTDIR/renewcertificate.sh\"" "\"$APPSERVICE_URL\"" "\"$ABS_CERDIR/$CERTNAME.pem\"" "\"$ABS_KEYDIR/$CERTNAME.key\"" "\"$ABS_ROOT\"" "10") | crontab -
