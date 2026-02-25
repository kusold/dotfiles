#!/usr/bin/env zsh
autoload command_exists

if command_exists yadm; then
	alias yadm-ignores="${EDITOR} ~/.config/yadm/gitignore"
fi

