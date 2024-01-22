#!/bin/bash

echo Running in $SHELL

# Install dotnet core if it is not installed

if ! [ -x "$(command -v dotnet)" ]; then
  wget https://dot.net/v1/dotnet-install.sh -O dotnet-install.sh
  chmod +x ./dotnet-install.sh
  ./dotnet-install.sh --version latest
fi


# Download csrrequest

# run csrrequest and enroll a certificate

# Install certificate where the WiFi profile is located