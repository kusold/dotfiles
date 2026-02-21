#!/usr/bin/env zsh
if [[ -d /opt/homebrew ]]; then
  export HOMEBREW_NO_ANALYTICS=1
  FPATH="/opt/homebrew/share/zsh/site-functions:${FPATH}"
fi
