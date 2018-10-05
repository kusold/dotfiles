#! /usr/bin/env bash

if command -v vim >/dev/null 2>&1; then
  echo "installing vim plugins"
  vim +PlugInstall +qall
fi

