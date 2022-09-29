#!/usr/bin/env zsh
autoload command_exists

# TODO: deferred loading means these don't get set

if command_exists base16_eighties; then
  alias dark=base16_eighties
fi

if command_exists base16_solarized-light; then
  alias light=base16_solarized-light
fi
