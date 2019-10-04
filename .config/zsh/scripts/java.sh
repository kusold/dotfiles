#!/usr/bin/env zsh
autoload command_exists

if command_exists jenv; then
  export PATH="$HOME/.jenv/bin:$PATH"
  eval "$(jenv init -)"
fi

# Change gradle home from ~/.gradle
export GRADLE_USER_HOME="$XDG_DATA_HOME"/gradle

