#!/usr/bin/env zsh
autoload command_exists

# BriteContent Github Go Directory
if [[ -d "$HOME/Development/auth0" ]]; then
  alias -g goauth0=$HOME/Development/auth0

 if command_exists vivaldi; then
   alias auth0-update='echo "$FG[yellow]Updating Vivaldi Core$FG[none]" && \
                       vivaldi update && \
                       echo "$FG[yellow]Updating auth0 repositories$FG[none]" && \
                       vivaldi pull && \
                       echo "$FG[yellow]Installing deps$FG[none]" && \
                       vivaldi install-deps'
 fi
fi

