#!/usr/bin/env zsh

# BriteContent Github Go Directory
if [[ -d "$GOPATH/src/github.com/BriteContent" ]]; then
  alias -g gobc=$GOPATH/src/github.com/BriteContent

  alias brite-servers="`npm bin -g`/nf start -j $GOPATH/src/github.com/BriteContent/Procfile"
fi

