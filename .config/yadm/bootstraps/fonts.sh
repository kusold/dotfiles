#! /usr/bin/env bash
system_type=$(uname -s)

font_directory="${HOME}/.local/share/fonts"

if [ "$system_type" = "Darwin" ]; then
	font_directory="${HOME}/Library/Fonts"
fi

mkdir -p "$font_directory"
cd "$font_directory" && curl --silent -fLo "Sauce Code Pro Nerd Font Complete Mono.ttf" https://github.com/ryanoasis/nerd-fonts/raw/master/patched-fonts/SourceCodePro/Regular/complete/Sauce%20Code%20Pro%20Nerd%20Font%20Complete%20Mono.ttf

