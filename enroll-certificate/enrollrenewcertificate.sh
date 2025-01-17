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

# Define the log file
LOG_FILE="$HOME/enrollrenewcertificate.log"

# Define the log level (DEBUG, INFO, ERROR), defaulting to INFO
LOG_LEVEL="${LOG_LEVEL:-INFO}"

# Logging functions
log_debug() {
    if [[ "$LOG_LEVEL" == "DEBUG" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [DEBUG] $1" >> "$LOG_FILE"
        # logger -t enrollrenewcertificate.sh -p user.debug "$1"
    fi
}

log_info() {
    if [[ "$LOG_LEVEL" == "DEBUG" || "$LOG_LEVEL" == "INFO" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $1" >> "$LOG_FILE"
        # logger -t enrollrenewcertificate.sh -p user.info "$1"
    fi
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $1" >> "$LOG_FILE"
    # logger -t enrollrenewcertificate.sh -p user.err "$1"
}


log_debug "Starting the certificate enrollment/renewal script"

log_debug "CERT_TYPE: $CERT_TYPE; CERT_COMMAND: $CERT_COMMAND"

ABS_KEY="$ABS_KEYDIR/$CERTNAME.key"
ABS_CER="$ABS_CERDIR/$CERTNAME.pem"

log_debug "APPSERVICE_URL: $APPSERVICE_URL"
log_debug "API_SCOPE: $API_SCOPE"
log_debug "CERTNAME: $CERTNAME"
log_debug "ABS_CERDIR: $ABS_CERDIR"
log_debug "ABS_KEYDIR: $ABS_KEYDIR"
log_debug "RENEWAL_THRESHOLD_DAYS: $RENEWAL_THRESHOLD_DAYS"
log_debug "ABS_KEY: $ABS_KEY"
log_debug "ABS_CER: $ABS_CER"

SECONDS_IN_DAY="86400"
if [[ -z "$RENEWAL_THRESHOLD_DAYS" ]]; then
    RENEWAL_THRESHOLD_DAYS="30"
fi
RENEWAL_THRESHOLD=$(($RENEWAL_THRESHOLD_DAYS * $SECONDS_IN_DAY))

log_debug "RENEWAL_THRESHOLD: $RENEWAL_THRESHOLD"

TEMP=$(mktemp -d tmpXXXXXXX)
TEMP_CSR="$TEMP/tmp.csr"
TEMP_KEY="$TEMP/tmp.key"
TEMP_P7B="$TEMP/tmp.p7b"
TEMP_PEM="$TEMP/tmp.pem"

log_debug "Temporary directory created: $TEMP"

trap "rm -r $TEMP" EXIT

if [[ -e "$ABS_CER" ]]; then
    log_info "Cert already exists in file $ABC_CER: enacting renewal protocol"
    OCSP_STATUS=$(openssl ocsp -issuer "$ABS_ROOT" -cert "$ABS_CER" -url "$APPSERVICE_URL/ocsp")
    TRIMMED_STATUS=$(echo "$OCSP_STATUS" | grep "good")
    log_debug "OCSP_STATUS: $OCSP_STATUS"
    log_debug "TRIMMED_STATUS: $TRIMMED_STATUS"
    if [[ ! -e "$ABS_KEY" ]]; then
        log_error "The certificate exists but no private key can be found, exiting"
        echo "The certificate exists but no private key can be found, exiting"
        exit 1
    fi
    if [ -z "${TRIMMED_STATUS}" ]; then
        log_error "OCSP failed - probably invalid paths or revoked certificate, exiting"
        echo "OCSP failed - probably invalid paths or revoked certificate, exiting" #can update this to reflect all of openssl ocsp errors
        exit 1
    fi
    if openssl x509 -checkend $RENEWAL_THRESHOLD -noout -in "$ABS_CER"; then
        log_info "Certificate not expiring within the threshold of $RENEWAL_THRESHOLD_DAYS days, exiting"
        echo "Certificate not expiring within the threshold of $RENEWAL_THRESHOLD_DAYS days, exiting"
        exit 1
    fi
    SUBJECT="/CN=Contoso"
    CURL_CMD='curl -X POST --data "@$TEMP_CSR" -H "Content-Type: application/pkcs10" --cert "$ABS_CER" --key "$ABS_KEY" "$APPSERVICE_URL/.well-known/est/simplereenroll"'
    EXTENSION1="subjectAltName=otherName:1.3.6.1.4.1.311.20.2.3;UTF8:$UPN" # remove this
else
    log_info "Cert does not exist in file $ABC_CER: enacting enrollment protocol"

    if ! command -v az &> /dev/null; then
        log_error "Azure CLI (az) is not installed. Please install it and try again."
        echo "Azure CLI (az) is not installed. Please install it and try again."
        exit 1
    else
        log_debug "Azure CLI (az) is installed."
    fi

    if [[ $CERT_TYPE == "user" ]]; then
        log_debug "CERT_TYPE is user"
        USER_OBJECT=$(az ad signed-in-user show)
        UPN=$(echo "$USER_OBJECT" | grep -oP '"mail": *"\K[^"]*')
        log_debug "USER_OBJECT: $USER_OBJECT"
        log_debug "UPN: $UPN"
        if [[ -z "$UPN" ]]; then
            log_error "No UPN found, exiting"
            echo "No UPN found, exiting"
            exit 1
        fi
        SUBJECT="/CN=$UPN"
        EXTENSION1="subjectAltName=otherName:1.3.6.1.4.1.311.20.2.3;UTF8:$UPN"

    else
        log_debug "CERT_TYPE is device"
        echo "DEVICE CERTIFICATE NOT YET IMPLEMENTED"
        log_error "Device certificate not yet implemented, exiting"
        DEVICE_ID=$(az rest --method get --uri "https://graph.microsoft.com/v1.0/me/managedDevices" --query "value[0].id" -o tsv)
        SUBJECT="/CN=$DEVICE_ID"
        EXTENSION1="subjectAltName=URI:IntuneDeviceId://{whatever the device ID is, not yet implemented}"
        exit 1
    fi

    az login --scope "$API_SCOPE/.default" --allow-no-subscriptions
    KV_TOKEN=$(az account get-access-token --scope "$API_SCOPE/.default" --query accessToken --output tsv)
    KV_TOKEN=$(echo "$KV_TOKEN" | sed 's/[[:space:]]*$//') # Remove trailing whitespace

    if [[ -z "$KV_TOKEN" ]]; then
        log_error "No token could be acquired, exiting"
        echo "No token could be acquired, exiting"
        exit 1
    fi

    CURL_CMD='curl -X POST --data "@$TEMP_CSR" -H "Content-Type: application/pkcs10" -H "Authorization: Bearer $KV_TOKEN" "$APPSERVICE_URL/.well-known/est/simpleenroll" >> "$TEMP_P7B"'
fi

EXTENSION2="extendedKeyUsage=1.3.6.1.5.5.7.3.2"

# Create a CSR
log_debug "Generating RSA key"
openssl genrsa -out "$TEMP_KEY" 4096
log_debug "Generating CSR"
openssl req -new -key "$TEMP_KEY" -sha256 -out "$TEMP_CSR" -subj "$SUBJECT" -addext "$EXTENSION1" -addext "$EXTENSION2"

# Create certificate
log_debug "Creating certificate"
echo "-----BEGIN PKCS7-----" > "$TEMP_P7B"
eval $CURL_CMD >> "$TEMP_P7B"
printf "\n-----END PKCS7-----" >> "$TEMP_P7B"
log_debug "Converting PKCS7 to PEM"
openssl pkcs7 -print_certs -in "$TEMP_P7B" -out "$TEMP_PEM"
if [ -f $TEMP_PEM ]; then
    log_debug "New PEM file created, copying key and certificate to $ABS_KEY and $ABS_CER, respectively"
    # only execute if new pem file created:
    cp "$TEMP_KEY" "$ABS_KEY"
    cp "$TEMP_PEM" "$ABS_CER"
    log_info "Certificate successfully enrolled/renewed"
else
    log_error "API endpoint returned an error"
    echo "API endpoint returned an error"
    exit 1
fi

# ABS_SCRIPTDIR="$HOME/.local/bin/cron/renewcertificate"
# mkdir -p "$ABS_SCRIPTDIR"
# cd ..
# cp renewcertificate.sh "$ABS_SCRIPTDIR/renewcertificate.sh"
# (crontab -l ; echo @daily "\"$ABS_SCRIPTDIR/renewcertificate.sh\"" "\"$APPSERVICE_URL\"" "\"$ABS_CERDIR/$CERTNAME.pem\"" "\"$ABS_KEYDIR/$CERTNAME.key\"" "\"$ABS_ROOT\"" "10") | crontab -
# (crontab -l ; echo @reboot "\"$ABS_SCRIPTDIR/renewcertificate.sh\"" "\"$APPSERVICE_URL\"" "\"$ABS_CERDIR/$CERTNAME.pem\"" "\"$ABS_KEYDIR/$CERTNAME.key\"" "\"$ABS_ROOT\"" "10") | crontab -
