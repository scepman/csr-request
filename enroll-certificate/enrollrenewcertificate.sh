#!/bin/bash

# Commands:
# -u for user certificate with auto-detection whether it is an initial enrollment or renewal
# -d for device certificate with auto-detection whether it is an initial enrollment or renewal
# -s for server certificate with auto-detection whether it is an initial enrollment or renewal
# -r for renewal
# -w for initial enrollment of a user
# -x for initial enrollment of a device
# -y for initial enrollment of a server certificate
# -c for submitting a present certificate signing request


# Arguments:
# $1 = Command to control the certificate enrollment/renewal process
# $2 = SCEPman app service URL
# $3 = API scope of SCEPman-api app registration
# $4 = Directory the certificate should be stored in as well as its private key and root certificate
# $5 = Desired name of certificate
# $6 = Desired name of private key
# $7 = Renewal threshold in days

# In case of server certificate, the script will use the following arguments additionally:
# $8 = Application (client) ID of the service principal
# $9 = Client secret of the service principal
# $10 = Tenant ID of the service principal


# Example use:
# sh enrollrenewcertificate.sh -u https://scepman.contoso.net/ api://b7d17d51-8b6d-45eb-b42b-3dae638cd5bc/Cert.Enroll ~/certs/ "myCertificate" "myKey" 30

# Default certificate type and command
CERT_TYPE="user"
CERT_COMMAND="auto"

# Parse command-line options
while getopts ":udsrwxyc" opt; do
  case ${opt} in
    u )
      CERT_TYPE="user"
      CERT_COMMAND="auto"
      EXTENSION2="extendedKeyUsage=1.3.6.1.5.5.7.3.2"
      ;;
    d )
      CERT_TYPE="device"
      CERT_COMMAND="auto"
      EXTENSION2="extendedKeyUsage=1.3.6.1.5.5.7.3.2"
      ;;
    s )
      CERT_TYPE="server"
      CERT_COMMAND="auto"
      EXTENSION2="extendedKeyUsage=1.3.6.1.5.5.7.3.1"
      ;;
    r )
      CERT_COMMAND="renewal"
      ;;
    w )
      CERT_TYPE="user"
      CERT_COMMAND="initial"
      EXTENSION2="extendedKeyUsage=1.3.6.1.5.5.7.3.2"
      ;;
    x )
      CERT_TYPE="device"
      CERT_COMMAND="initial"
      EXTENSION2="extendedKeyUsage=1.3.6.1.5.5.7.3.2"
      ;;
    y )
      CERT_TYPE="server"
      CERT_COMMAND="initial"
      EXTENSION2="extendedKeyUsage=1.3.6.1.5.5.7.3.1"
      ;;
    c )
      CERT_COMMAND="csr"
      ;;
    \? )
      echo "Usage: -u for user certificate, -d for device certificate, -r for renewal, -w for initial enrollment of a user, -x for initial enrollment of a device, -s for server certificate, -y for initial enrollment of a server certificate, -c for CSR submission" 1>&2
      exit 1
      ;;
  esac
done
shift $((OPTIND -1))

# Parameters applicable to all certificate types
APPSERVICE_URL="$1"
API_SCOPE="$2"
CERT_DIR=$(readlink -f "$3")
CERT_NAME="$4"
KEY_NAME="$5"

RENEWAL_THRESHOLD_DAYS="$6"

if [[ $CERT_TYPE == "server" ]]; then
    AUTH_CLIENT_ID="$7"
    AUTH_CLIENT_SECRET="$8"
    AUTH_TENANT_ID="$9"
    SUBJECT="${10}"
    EXTENSION1="subjectAltName=${11}"

    # Add the .default scope for service principal authentication
    API_SCOPE="$API_SCOPE/.default"
fi

if [[ $CERT_COMMAND == "csr" ]]; then
    AUTH_CLIENT_ID="$7"
    AUTH_CLIENT_SECRET="$8"
    AUTH_TENANT_ID="$9"
    CSR_PATH="${10}"
fi

# Concat absolute paths
KEY_DIR=$CERT_DIR
CERT_PATH="$CERT_DIR/$CERT_NAME.pem"
ROOT_PATH="$CERT_DIR/SCEPmanRoot.cer"
KEY_PATH="$CERT_DIR/$KEY_NAME"

# Define the log level (DEBUG, INFO, ERROR), defaulting to INFO
LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_FILE="${0##*/}.$(date '+%Y-%m-%d').log"

# Logging functions
log() {
	LEVEL=$1
	MESSAGE=$2

    if [ "$LEVEL" != "debug" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [$LEVEL] $MESSAGE" | tee -a "$LOG_FILE"
    fi

    if [ "$LEVEL" == "debug" ] && [ "$LOG_LEVEL" == "debug" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [$LEVEL] $MESSAGE" | tee -a "$LOG_FILE"
    fi
}

check_certificate() {
    cert_path=$1
    root_path=$2
    key_path=$3
    appservice_url=$4
    renewal_threshold_days=$5

    if [[ ! -e "$cert_path" ]]; then
        # Certificate does not exist
        echo 1
        return 0
    fi

    OCSP_RESPONSE=$(openssl ocsp -issuer "$root_path" -cert "$cert_path" -url "$appservice_url/ocsp")
    OCSP_STATUS=$(echo "$OCSP_RESPONSE" | grep "good")

    if [[ ! -e "$key_path" ]]; then
        # The certificate exists but no private key can be found
        echo 2
        return 0
    fi

    if [ -z "${OCSP_STATUS}" ]; then
        # OCSP failed - probably invalid paths or revoked certificate
        echo 3
        return 0
    fi

    SECONDS_IN_DAY="86400"
    if [[ -z "$renewal_threshold_days" ]]; then
        renewal_threshold_days="30"
    fi
    renewal_threshold=$(($renewal_threshold_days * $SECONDS_IN_DAY))

    EXPIRATION_STATE=$(openssl x509 -checkend $renewal_threshold -noout -in "$cert_path")
    if [[ $EXPIRATION_STATE == "Certificate will not expire" ]]; then
        # Certificate does not expire withing the threshold
        echo 4
        return 0
    fi

    # Return truthy in case the certificate is valid and needs renewal
    echo 0
    return 0
}

get_root_certificate() {
    appservice_url=$1
    root_path=$2

    # Make sure we have a root certificate to work with
    rootca_url="$(echo "$appservice_url" | sed 's:/*$::')/certsrv/mscep/mscep.dll/pkiclient.exe?operation=GetCACert"

    log info "Download root certificate to $root_path"
    log debug "Download URL is $rootca_url"
    curl --silent -X GET -H "Content-Type: application/pkcs10" $rootca_url -o $root_path
}

verify_az_installation() {
    log debug "Check if Azure CLI is installed"
    if ! command -v az &> /dev/null; then
        log error "Azure CLI is not installed, exiting"
        exit 1
    fi
}

authenticate_interactive() {
    api_scope=$1

    # Disable the subscriptions selection
    az config set core.login_experience_v2=off
    az login --scope "$api_scope" --allow-no-subscriptions
}

authenticate_service_principal() {
    api_scope=$1
    client_id=$2
    client_secret=$3
    tenant_id=$4

    log debug "Authenticate service principal"
    az login --scope "$api_scope" --service-principal --username $client_id --password $client_secret --tenant $tenant_id --allow-no-subscriptions
}

get_access_token() {
    api_scope=$1

    auth_token=$(az account get-access-token --scope "$api_scope" --query accessToken --output tsv)
    auth_token=$(echo "$auth_token" | sed 's/[[:space:]]*$//') # Remove trailing whitespace

    if [[ -z "$auth_token" ]]; then
        log error "No token could be acquired, exiting"
        exit 1
    fi

    echo $auth_token
}

log debug "Starting the certificate enrollment/renewal script"

log debug "CERT_TYPE: $CERT_TYPE; CERT_COMMAND: $CERT_COMMAND"

log debug "APPSERVICE_URL: $APPSERVICE_URL"
log debug "API_SCOPE: $API_SCOPE"
log debug "CERT_NAME: $CERT_NAME"
log debug "CERT_PATH: $CERT_PATH"
log debug "KEY_PATH: $KEY_PATH"
log debug "RENEWAL_THRESHOLD_DAYS: $RENEWAL_THRESHOLD_DAYS"

if [[ $CERT_TYPE == "server" ]]; then
    log debug "AUTH_CLIENT_ID: $AUTH_CLIENT_ID"
    log debug "AUTH_TENANT_ID: $AUTH_TENANT_ID"
    log debug "SUBJECT: $SUBJECT"
    log debug "EXTENSION: $EXTENSION1"
fi

# Verify directories
if ! [ -d $CERT_DIR ]; then
  mkdir -p $CERT_DIR
fi

if ! [ -d $KEY_DIR ]; then
  mkdir -p $KEY_DIR
fi


TEMP=$(mktemp -d tmpXXXXXXX)
TEMP_CSR="$TEMP/tmp.csr"
TEMP_KEY="$TEMP/tmp.key"
TEMP_P7B="$TEMP/tmp.p7b"
TEMP_PEM="$TEMP/tmp.pem"

log debug "Temporary directory created: $TEMP"

trap "rm -r $TEMP" EXIT

# Check if the certificate exists and requires renewal
if [[ $CERT_COMMAND  == "renewal" || $CERT_COMMAND  == "auto" ]]; then
    log debug "Checking certificate status"

    # Make sure we have a root certificate
    if ! [ -f "$ROOT_PATH" ]; then
        log info "No root certificate has been passed"
        log info "Download root certificate to $ROOT_PATH"
        log debug "Download URL is $ROOT_PATH"
        get_root_certificate $APPSERVICE_URL $ROOT_PATH
    else
        log info "Root certificate found in $ROOT_PATH"
    fi

    CERT_STATUS=$(check_certificate $CERT_PATH $ROOT_PATH $KEY_PATH $APPSERVICE_URL $RENEWAL_THRESHOLD_DAYS)

    log debug "CERT_STATUS: $CERT_STATUS"

    case $CERT_STATUS in
        1)
            if [[ $CERT_COMMAND == "renewal" ]]; then
                log info "No certificate found but command is renewal, exiting"
                exit 0
            else 
                log info "No certificate found but command is auto. Enacting enrollment protocol"
                CERT_COMMAND="initial"
            fi
            ;;
        2)
            log error "The certificate exists but no private key can be found, exiting"
            exit 1
            ;;
        3)
            log error "OCSP failed - probably invalid paths or revoked certificate, exiting"
            exit 1
            ;;
        4)
            log info "Certificate not expiring within the threshold of $RENEWAL_THRESHOLD_DAYS days, exiting"
            exit 0
            ;;
        0)
            log info "Certificate is valid and needs renewal"
            CERT_COMMAND="renewal"
            ;;
        *)
            log error "Unknown certificate status, exiting"
            exit 1
            ;;
    esac
fi

if [ $CERT_COMMAND == "renewal" ]; then
    log info "Certificate $CERT_PATH will be renewed"

    # Set certificate variables for renewal
    SUBJECT="/CN=Contoso"
    CURL_CMD='curl -X POST --data "@$TEMP_CSR" -H "Content-Type: application/pkcs10" --cert "$CERT_PATH" --key "$KEY_PATH" "$APPSERVICE_URL/.well-known/est/simplereenroll"'
    EXTENSION1="subjectAltName=otherName:1.3.6.1.4.1.311.20.2.3;UTF8:$UPN" # remove this

elif [[ $CERT_COMMAND == "initial" ]]; then
    if [ -f "$CERT_PATH" ]; then
        log error "Certificate file is already present but command "initial" is passed. Exiting"
        exit 1
    fi

    log info "Certificate $CERT_PATH will be enrolled"

    verify_az_installation

    if [[ $CERT_TYPE == "user" ]]; then
        log debug "CERT_TYPE is user"

        # Authenticate and get access token
        authenticate_interactive $API_SCOPE
        KV_TOKEN=$(get_access_token $API_SCOPE)

        USER_OBJECT=$(az ad signed-in-user show)
        UPN=$(echo "$USER_OBJECT" | grep -oP '"userPrincipalName": *"\K[^"]*')
        log debug "USER_OBJECT: $USER_OBJECT"
        log debug "UPN: $UPN"
        if [[ -z "$UPN" ]]; then
            log error "No UPN found, exiting"
            exit 1
        fi
        SUBJECT="/CN=$UPN"
        EXTENSION1="subjectAltName=otherName:1.3.6.1.4.1.311.20.2.3;UTF8:$UPN"

        # Concat curl command
        CURL_CMD='curl -X POST --data "@$TEMP_CSR" -H "Content-Type: application/pkcs10" -H "Authorization: Bearer $KV_TOKEN" "$APPSERVICE_URL/.well-known/est/simpleenroll" >> "$TEMP_P7B"'
    elif [[ $CERT_TYPE == "device" ]]; then
        log debug "CERT_TYPE is device"

        # Authenticate and get access token
        authenticate_interactive $API_SCOPE
        KV_TOKEN=$(get_access_token $API_SCOPE)
        
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

        # Concat curl command
        CURL_CMD='curl -X POST --data "@$TEMP_CSR" -H "Content-Type: application/pkcs10" -H "Authorization: Bearer $KV_TOKEN" "$APPSERVICE_URL/.well-known/est/simpleenroll" >> "$TEMP_P7B"'
    elif [[ $CERT_TYPE == "server" ]]; then
        log debug "CERT_TYPE is server"

        # Authenticate and get access token
        authenticate_service_principal $API_SCOPE $AUTH_CLIENT_ID $AUTH_CLIENT_SECRET $AUTH_TENANT_ID
        KV_TOKEN=$(get_access_token $API_SCOPE)

        # Concat curl command
        CURL_CMD='curl -X POST --data "@$TEMP_CSR" -H "Content-Type: application/pkcs10" -H "Authorization: Bearer $KV_TOKEN" "$APPSERVICE_URL/.well-known/est/simpleenroll" >> "$TEMP_P7B"'

    else
        log error "Invalid certificate type, exiting"
        exit 1
    fi
fi

if [[ $CERT_COMMAND == "csr" ]]; then
    # Verify passed csr and key
    if [[ ! -f $CSR_PATH ]]; then
        log error "CSR file not found, exiting"
        exit 1
    fi

    if [[ ! -f $KEY_PATH ]]; then
        log error "Private key not found, exiting"
        exit 1
    fi

    # Authenticate and get access token
    log debug "Authenticate and get access token"
    authenticate_service_principal $API_SCOPE $AUTH_CLIENT_ID $AUTH_CLIENT_SECRET $AUTH_TENANT_ID
    KV_TOKEN=$(get_access_token $API_SCOPE)

    log info "Submitting CSR"
    log debug "CSR_PATH: $CSR_PATH"

    # Concat curl command
    CURL_CMD='curl -X POST --data "@$CSR_PATH" -H "Content-Type: application/pkcs10" -H "Authorization: Bearer $KV_TOKEN" "$APPSERVICE_URL/.well-known/est/simpleenroll" >> "$TEMP_P7B"'
else
    # Create a CSR
    log debug "Generating RSA key"
    openssl genrsa -out "$TEMP_KEY" 4096
    log debug "Generating CSR"
    log debug "SUBJECT: $SUBJECT"
    log debug "EXTENSION1: $EXTENSION1"
    log debug "EXTENSION2: $EXTENSION2"

    if [ -z ${var+x} ]; then
        log debug "EXTENSION2 is unset. Assume Renewal. Skipping in csr"
        openssl req -new -key "$TEMP_KEY" -sha256 -out "$TEMP_CSR" -subj "$SUBJECT" -addext "$EXTENSION1"
    else
        openssl req -new -key "$TEMP_KEY" -sha256 -out "$TEMP_CSR" -subj "$SUBJECT" -addext "$EXTENSION1" -addext "$EXTENSION2"
    fi
fi

# Create certificate
log debug "Creating certificate"
log debug "CURL_CMD: $CURL_CMD"
echo "-----BEGIN PKCS7-----" > "$TEMP_P7B"
eval $CURL_CMD >> "$TEMP_P7B"
printf "\n-----END PKCS7-----" >> "$TEMP_P7B"
log debug "Converting PKCS7 to PEM"
openssl pkcs7 -print_certs -in "$TEMP_P7B" -out "$TEMP_PEM"
if [ -f $TEMP_PEM ]; then
    log debug "New PEM file created, copying key and certificate to $KEY_PATH and $CERT_PATH, respectively"
    # only execute if new pem file created:

    # Only copy temp key for non csr scenarios
    if ! [[ $CERT_COMMAND == "csr" ]]; then
        cp "$TEMP_KEY" "$KEY_PATH"
    fi
    
    cp "$TEMP_PEM" "$CERT_PATH"
    log info "Certificate successfully enrolled/renewed"
else
    log error "API endpoint returned an error"
    exit 1
fi

# ABS_SCRIPTDIR="$HOME/.local/bin/cron/renewcertificate"
# mkdir -p "$ABS_SCRIPTDIR"
# cd ..
# cp renewcertificate.sh "$ABS_SCRIPTDIR/renewcertificate.sh"
# (crontab -l ; echo @daily "\"$ABS_SCRIPTDIR/renewcertificate.sh\"" "\"$APPSERVICE_URL\"" "\"$ABS_CERDIR/$CERTNAME.pem\"" "\"$ABS_KEY_DIR/$CERTNAME.key\"" "\"$ABS_ROOT\"" "10") | crontab -
# (crontab -l ; echo @reboot "\"$ABS_SCRIPTDIR/renewcertificate.sh\"" "\"$APPSERVICE_URL\"" "\"$ABS_CERDIR/$CERTNAME.pem\"" "\"$ABS_KEY_DIR/$CERTNAME.key\"" "\"$ABS_ROOT\"" "10") | crontab -
