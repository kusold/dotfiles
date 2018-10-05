#!/usr/bin/env zsh

if [[ -d "/usr/local/share/dotnet" ]]; then
  export PATH=$PATH:/usr/local/share/dotnet
  export DOTNET_CLI_TELEMETRY_OPTOUT=true
fi

