#! /usr/bin/env bash

if command -v npm >/dev/null 2>&1; then
  echo "installing global npm packages"
  npm install -g \
    @ansible/ansible-language-server@latest \
    @microsoft/compose-language-service \
    babel-eslint@latest \
    bash-language-server@latest \
    clone-org-repos@latest \
    diagnostic-languageserver@latest \
    dockerfile-language-server-nodejs@latest \
    editorconfig-checker@latest \
    eslint-plugin-react@latest \
    eslint@latest \
    foreman@latest \
    jshint-jsx@latest \
    jshint@latest \
    neovim@latest \
    sql-language-server@latest \
    yaml-language-server@latest
fi
