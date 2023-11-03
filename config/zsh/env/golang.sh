#!/usr/bin/env zsh
# Go Lang Setup
if [[ -d "$HOME/Development/go/" ]]; then
  export GOPATH=$HOME/Development/go
fi

if [[ -d "$GOPATH/bin/" ]]; then
  export PATH=$GOPATH/bin:$PATH
fi

if [[ -d "/usr/local/go" ]]; then
  export PATH=$PATH:/usr/local/go/bin
  export GOROOT=/usr/local/go/
fi

if [[ -d "/usr/local/opt/go/libexec" ]]; then
  export PATH=$PATH:/usr/local/opt/go/libexec
  export GOROOT=/usr/local/opt/go/libexec
fi

