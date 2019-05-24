#! /usr/bin/env bash

if command -v go >/dev/null 2>&1; then
  echo "installing global go packages"
	go get -u golang.org/x/lint
	go get -u golang.org/x/tools/cmd/gopls
	go get -u golang.org/x/tools/cmd/goimports
fi
