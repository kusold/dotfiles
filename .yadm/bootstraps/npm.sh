#! /usr/bin/env bash

if command -v npm >/dev/null 2>&1; then
  echo "installing global npm packages"
  npm install -g \
    babel-eslint@latest \
    clone-org-repos@latest \
    editorconfig-checker@latest \
    eslint-plugin-react@latest \
    eslint@latest \
    foreman@latest \
    lerna@latest \
    jshint-jsx@latest \
    jshint@latest \
    tern@latest \
    neovim@latest \
		dockerfile-language-server-nodejs@latest
fi
