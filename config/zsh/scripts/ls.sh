#!/usr/bin/env zsh
autoload is_callable

# colorize ls
if is_callable 'dircolors'; then
  # GNU Core Utilities
  alias ls='ls --group-directories-first'

  if [[ -s "$HOME/.dir_colors" ]]; then
    eval "$(dircolors --sh "$HOME/.dir_colors")"
  else
    eval "$(dircolors --sh)"
  fi

  alias ls="${aliases[ls]:-ls} --color=auto"
else
  # BSD Core Utilities
  # Define colors for BSD ls.
  export LSCOLORS='exfxcxdxbxGxDxabagacad'

  # Define colors for the completion system.
  export LS_COLORS='di=34:ln=35:so=32:pi=33:ex=31:bd=36;01:cd=33;01:su=31;40;07:sg=36;40;07:tw=32;40;07:ow=33;40;07:'

  alias ls="${aliases[ls]:-ls} -G"
fi
