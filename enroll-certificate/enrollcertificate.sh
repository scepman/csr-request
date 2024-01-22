#!/bin/bash

echo Running in $SHELL

# Install dotnet core if it is not installed

$dotnetcommand = dotnet
if ! [ -x "$(command -v dotnet)" ]; then
  wget https://dot.net/v1/dotnet-install.sh -O dotnet-install.sh
  chmod +x ./dotnet-install.sh
  ./dotnet-install.sh --version latest
  $dotnetcommand = $HOME/.dotnet/dotnet
fi

# Download CsrClient

wget https://github.com/scepman/csr-request/releases/download/alpha-test/enroll-certificate.tgz -O enroll-certificate.tgz
mkdir csrclient
cd csrclient
tar -xvf enroll-certificate.tgz

# run CsrClient and enroll a certificate

dotnet CsrClient.dll csr $1 $2

# Install client certificate where the WiFi profile is located
