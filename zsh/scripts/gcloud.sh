#!/usr/bin/env zsh

# Add gcloud
if [[ -d "$HOME/google-cloud-sdk" ]]; then
  # The next line enables bash completion for gcloud.
  source "$HOME/google-cloud-sdk/completion.zsh.inc"
  # The next line enables shell command completion for gcloud.
  source "$HOME/google-cloud-sdk/path.zsh.inc"

  function gcloud-ssh () {
    if [[ -n $1 ]]; then
      gcloud compute ssh --ssh-flag="-A" $1 $2 $3
    else
      echo "Please pass in the instance name"
    fi
  }
fi


