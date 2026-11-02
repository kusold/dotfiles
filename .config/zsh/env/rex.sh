#!/usr/bin/env zsh

# Rex puts its CLI dir at the front of PATH when it opens a terminal, but
# nix-darwin's set-environment (/etc/zshenv) rebuilds PATH before user files
# run, which drops it. REX_BIN_DIR survives as a variable, so put the CLI
# back on PATH.
# https://www.superlogical.com/rex/docs/automate/cli
if [[ -n "${REX_BIN_DIR:-}" && -x "${REX_BIN_DIR}/rex" ]]; then
  if [[ ":${PATH}:" != *":${REX_BIN_DIR}:"* ]]; then
    export PATH="${REX_BIN_DIR}:${PATH}"
  fi
fi
