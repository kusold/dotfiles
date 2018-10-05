#! /usr/bin/env bash

if command -v tmux >/dev/null 2>&1; then
  echo "installing tmux plugins"
  ${HOME}/.tmux/plugins/tpm/bin/install_plugins
fi

