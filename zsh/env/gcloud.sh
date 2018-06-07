#!/usr/bin/env zsh

# Add gcloud
if [[ -d "$HOME/google-cloud-sdk" ]]; then
  export PATH=$HOME/google-cloud-sdk/bin:$PATH
fi

