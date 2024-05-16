#!/bin/bash

# Arguments:
# $1 = SCEPman app service URL
# $2 = API scope of SCEPman-api app registration
# $3 = Client ID of special app registration (e.g. Linux-SCEPman-Client app reg)
# $4 = Tenant ID
# $5 = Desired name of certificate
# $6 = Directory where cert is to be installed
# $7 = Directory where key is to be installed
# $8 = Root certificate

APPSERVICE_URL="$1"
CERTNAME="$5"
ABS_CERDIR=$(readlink -f "$6")
ABS_KEYDIR=$(readlink -f "$7")
ABS_ROOT=$(readlink -f "$8")
ABS_SCRIPTDIR=$(readlink -f ".")

# Example use:
# sh enrollcertificate.sh https://your-scepman-domain.azurewebsites.net/ api://123guid 123-clientid-123  2323-tenantid-233 cert-name cert-directory key-directory root.pem

echo Running in $SHELL

# Install dotnet core if it is not installed
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

# run CsrClient and enroll a certificate
eval "$dotnetcommand CsrClient.dll csr $APPSERVICE_URL $2 $3 interactive $4"

# Install client certificates in correct locations and convert to pkcs12 format
openssl pkcs12 -in "my-certificate.pfx" -nokeys -out "$ABS_CERDIR/$CERTNAME.pem"
openssl pkcs12 -in "my-certificate.pfx" -nodes -nocerts -out "$ABS_KEYDIR/$CERTNAME.key" 

# Create cronjob for mTLS renewal of certificates using renewcertificate.sh script.
# How often should the cronjob go? Should it depnd on when the certificate is meant to expire? Or just 
# every day or some fixed interval

# TODO storing renewal script in a different place
(crontab -l ; echo @daily "\"$ABS_SCRIPTDIR/renewcertificate.sh\"" "\"$APPSERVICE_URL\"" "\"$ABS_CERDIR/$CERTNAME.pem\"" "\"$ABS_KEYDIR/$CERTNAME.key\"" "\"$ABS_ROOT\"" ) | crontab -
(crontab -l ; echo @reboot "\"$ABS_SCRIPTDIR/renewcertificate.sh\"" "\"$APPSERVICE_URL\"" "\"$ABS_CERDIR/$CERTNAME.pem\"" "\"$ABS_KEYDIR/$CERTNAME.key\"" "\"$ABS_ROOT\"" ) | crontab -