#!/bin/bash

echo Running in $SHELL

# Install dotnet core if it is not installed
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
eval "$dotnetcommand CsrClient.dll csr $1 $2"

# Install client certificate where the WiFi profile is located
certname="my-certificate" # TODO: Change how certname is acquired.
sudo openssl pkcs12 -in $certname.pfx -out /etc/ssl/certs/$certname.pem -nodes #-nodes bypasses private key encryption
sudo openssl pkcs12 -in $certname.pfx -nocerts -out /etc/ssl/private/$certname.key 

# TODO? Remove installed files?
# TODO: Update hardcoded values in csrclient. 