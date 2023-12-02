#!/usr/bin/env zsh
autoload command_exists

if command_exists kubectl; then
  kubectl () {
    command kubectl $*
    if [[ -z $KUBECTL_COMPLETE ]]
    then
        source <(command kubectl completion zsh)
        KUBECTL_COMPLETE=1
    fi
  }
fi
