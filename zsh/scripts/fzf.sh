#!/usr/bin/env zsh

autoload command_exists

# Source fzf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# Use ripgrep
if command_exists rg; then
  export FZF_DEFAULT_COMMAND='rg --files --no-ignore --hidden --follow --glob "!{.git,node_modules}/*"'
  alias search-content='rg --smart-case --no-line-number --no-heading . |fzf --preview "head -$LINES {1}" --delimiter=:'
fi
