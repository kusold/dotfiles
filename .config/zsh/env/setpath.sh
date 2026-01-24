#!/usr/bin/env zsh

# Add home bin
if [[ -d "$HOME/.bin/" ]]; then
  export PATH=$HOME/.bin:$PATH
fi
if [[ -d "$HOME/bin/" ]]; then
  export PATH=$HOME/bin:$PATH
fi

# Add homebrew
if [[ -d "/opt/homebrew/bin/" ]]; then
  export PATH=/opt/homebrew/bin:$PATH
fi
# Add locally bins
if [[ -d "/opt/local/bin/" ]]; then
  export PATH=/opt/local/bin:$PATH
fi

# Add locally bins
if [[ -d "/usr/sbin/" ]]; then
  export PATH=$PATH:/usr/sbin:/sbin
fi

# Add locally bins
if [[ -d "/usr/local/" ]]; then
  export PATH=$PATH:/usr/local
fi

# Add home-manager
if [[ -d "${HOME}/.nix-profile/bin" ]]; then
  export PATH=${HOME}/.nix-profile/bin:$PATH
fi
