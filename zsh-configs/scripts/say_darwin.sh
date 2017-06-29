#!/usr/bin/env zsh
autoload is_darwin

if is_darwin; then
  function sayall () {
    text=$1
    for voice in `say -v '?' | awk '{print $1}'`; do
      echo $voice
      say -v $voice "${text}";
    done
  }
fi

