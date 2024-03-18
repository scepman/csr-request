#!/bin/bash

# Arguments:
# $1 = SCEPman app service URL
# $2 = API scope of SCEPman-api app registration
# $3 = Client ID of special app registration (e.g. Linux-SCEPman-Client app reg)
# $4 = Tenant ID

echo Running in $SHELL

# Install dotnet core if it is not installed
# Do we need to make sure the correct version of dotnet is installed? 
dotnetcommand="dotnet"
if ! [ -x "$(command -v dotnet)" ]; then
  if [ ! -e "$HOME/.dotnet/dotnet" ]; then
    wget https://dot.net/v1/dotnet-install.sh -O dotnet-install.sh
    chmod +x ./dotnet-install.sh
    ./dotnet-install.sh --version latest --channel 7.0
  fi
  dotnetcommand="$HOME/.dotnet/dotnet"
fi

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
eval "$dotnetcommand CsrClient.dll csr $1 $2 $3 interactive $4"

# Install client certificate where the WiFi profile is located
certname="my-certificate" # TODO: Change how certname is acquired.
# Felix says should be stored in /etc/NetworkManager/system-connections but not sure if the system-connections dir will exist
sudo openssl pkcs12 -in $certname.pfx -nokeys -out /etc/ssl/certs/$certname.pem -nodes #-nodes bypasses private key encryption.
sudo openssl pkcs12 -in $certname.pfx -nocerts -out /etc/ssl/private/$certname.key 

# Create cronjob for mTLS renewal of certificates using renewcertificate.sh script.
# How often should the cronjob go? Should it depnd on when the certificate is meant to expire? Or just 
# every day or some fixed interval
(crontab -l ; echo "00 00 * * * ./renewcertificate.sh $certname $1") | crontab -

# TODO? Remove installed files?
