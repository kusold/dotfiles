#!/usr/bin/env zsh
autoload command_exists

# BriteContent Github Go Directory
if [[ -d "$HOME/Development/auth0" ]]; then
  alias -g goa0=$HOME/Development/auth0

 if command_exists vivaldi; then
   alias auth0-update='echo "$FG[yellow]Updating Vivaldi Core$FG[none]" && \
                       vivaldi update && \
                       echo "$FG[yellow]Updating auth0 repositories$FG[none]" && \
                       vivaldi pull && \
                       echo "$FG[yellow]Installing deps$FG[none]" && \
                       vivaldi install-deps'

   alias auth0-start='vivaldi down && vivaldi up mongo redis rabbit limitd && sleep 120 && vivaldi up && vivaldi logs'
 fi
fi

local guardianScripts="$HOME/Development/auth0/guardian-scripts"
if [[ -d $guardianScripts ]]; then
	export PATH="${guardianScripts}:${PATH}"
fi

