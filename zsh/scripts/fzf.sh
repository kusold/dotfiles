#!/usr/bin/env zsh

autoload command_exists

# Source fzf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

if command_exists fzf; then
  # Use ripgrep
  if command_exists rg; then
    export FZF_DEFAULT_COMMAND='rg --files --no-ignore --hidden --follow --glob "!{.git,node_modules}/*"'
    alias search-content='rg --smart-case --no-line-number --no-heading . |fzf --preview "head -$LINES {1}" --delimiter=:'
  fi


  if command_exists git; then
    git-show() {
      local g=(
        git log
        --graph
        --format='%C(auto)%h%d %s %C(white)%C(bold)%cr'
        --color=always
        "$@"
      )

      local fzf=(
        fzf
        --ansi
        --reverse
        --tiebreak=index
        --no-sort
        --bind=ctrl-s:toggle-sort
        --preview 'f() { set -- $(echo -- "$@" | grep -o "[a-f0-9]\{7\}"); [ $# -eq 0 ] || git show --color=always $1; }; f {}'
      )
      $g | $fzf
    }
  fi
fi
