#!/usr/local/env zsh
autoload command_exists;
autoload command_missing;

if command_missing python; then
	if command_exists python3; then
		alias python=python3
	fi
fi

# Python
if command_exists pyenv-virtualenv-init; then
  eval "$(pyenv virtualenv-init -)";
fi
if command_exists virtualenv; then
  # pip should only run if there is a virtualenv currently activated
  export PIP_REQUIRE_VIRTUALENV=true
fi


