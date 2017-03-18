#!/usr/bin/env zsh
autoload command_exists

# BriteContent Github Go Directory
if [[ -d "$GOPATH/src/github.com/BriteContent" ]]; then
  alias -g gobc=$GOPATH/src/github.com/BriteContent

 if command_exists npm; then
   alias brite-servers="`npm bin -g`/nf start -j $GOPATH/src/github.com/BriteContent/Procfile"
 fi
fi

