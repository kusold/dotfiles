#!/usr/bin/env zsh

# Determine the platform that we are using

unameres=`uname`
if [[ "$unameres" == 'Linux' ]]; then
  export PLATFORM='linux'
fi
if [[ "$unameres" == 'Darwin' ]]; then
  export PLATFORM='darwin'
fi

