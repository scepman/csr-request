#!/bin/bash

# Arguments:
# $1 = SCEPman app service URL
# $2 = API scope of SCEPman-api app registration
# $3 = Client ID of special app registration (e.g. Linux-SCEPman-Client app reg)
# $4 = Tenant ID
# $5 = Directory where cert is to be installed
# $6 = Directory where key is to be installed
# $7 = Root certificate

# TODO Give variables names
APPSERVICE_URL="$1"
ABS_CERDIR=$(readlink -f "$5")
ABS_KEYDIR=$(readlink -f "$6")
ABS_ROOT=$(readlink -f "$7")
ABS_SCRIPTDIR=$(readlink -f ".")


# Example use:
# ./enrollcertificate.sh https://app-scepman-csz5hqanxf6cs.azurewebsites.net/ api://dae9ad68-36a4-4f19-b663-cf2f4e81c95f 0f07dac8-7064-4203-a883-e86c0f4bb98a 9b3e2dea-5dd4-4f67-b0f5-fcc0ae9af63c . . /etc/ssl/certs/scepman-dxun-root.pem

# Need to instruct customer on how to set up the special app registration

echo Running in $SHELL

# Install dotnet core if it is not installed
# Do we need to make sure the correct version of dotnet is installed? 
# The outside if statements don't work
dotnetcommand="dotnet"
# if ! [ -x "$(command -v dotnet)" ]; then
  if [ ! -e "$HOME/.dotnet/dotnet" ]; then
    wget https://dot.net/v1/dotnet-install.sh -O dotnet-install.sh
    chmod +x ./dotnet-install.sh
    ./dotnet-install.sh --version latest --channel 7.0
  fi
  dotnetcommand="$HOME/.dotnet/dotnet"
# fi

# Download CsrClient
if [ ! -e "$HOME/enroll-certificate.tgz" ]; then
  mkdir csrclient
  wget https://github.com/scepman/csr-request/releases/download/alpha-test/enroll-certificate.tgz -O csrclient/enroll-certificate.tgz
  cd csrclient
  tar -xvzf enroll-certificate.tgz
else
  cd csrclient
fi

# # run CsrClient and enroll a certificate
eval "$dotnetcommand CsrClient.dll csr $APPSERVICE_URL $2 $3 interactive $4"

# Install client certificate where the WiFi profile is located
CERTNAME="my-certificate" # TODO: Change how certname is acquired. From parameters?
# Felix says should be stored in /etc/NetworkManager/system-connections but not sure if the system-connections dir will exist by default
openssl pkcs12 -in "$CERTNAME.pfx" -nokeys -out "$ABS_CERDIR/$CERTNAME.pem" #-nodes #-nodes bypasses private key encryption.
openssl pkcs12 -in "$CERTNAME.pfx" -nodes -nocerts -out "$ABS_KEYDIR/$CERTNAME.key" 

# Create cronjob for mTLS renewal of certificates using renewcertificate.sh script.
# How often should the cronjob go? Should it depnd on when the certificate is meant to expire? Or just 
# every day or some fixed interval

# TODO work out where to store renewal script
# (crontab -l ; echo @daily "\"$ABS_SCRIPTDIR/renewcertificate.sh\"" "\"$CERTNAME\"" "\"$APPSERVICE_URL\"" "\"$ABS_CERDIR\"" "\"$ABS_KEYDIR\"" "\"$ABS_ROOT\"") | crontab -
(crontab -l ; echo @reboot sh -x "\"$ABS_SCRIPTDIR/renewcertificate.sh\"" "\"$CERTNAME\"" "\"$APPSERVICE_URL\"" "\"$ABS_CERDIR\"" "\"$ABS_KEYDIR\"" "\"$ABS_ROOT\"" " >> \"/mnt/c/Users/BenGodwin/OneDrive - glueckkanja-gab/Desktop/csr-request/enroll-certificate/output.txt\" 2>&1" ) | crontab -