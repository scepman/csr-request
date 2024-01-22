#!/bin/bash

echo Running in $SHELL

# Install dotnet core

curl -sSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel 3.1 --install-dir /usr/share/dotnet

# Download csrrequest

# run csrrequest and enroll a certificate

# Install certificate where the WiFi profile is located