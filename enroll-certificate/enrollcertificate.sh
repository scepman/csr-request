#!/bin/bash

echo Running in $SHELL

# Install dotnet core if it is not installed

$dotnetcommand = "dotnet"
if ! [ -x "$(command -v dotnet)" ]; then
  if [ ! -e "$HOME/.dotnet/dotnet" ]; then
    wget https://dot.net/v1/dotnet-install.sh -O dotnet-install.sh
    chmod +x ./dotnet-install.sh
    ./dotnet-install.sh --version latest
  fi
  $dotnetcommand = "$HOME/.dotnet/dotnet"
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
