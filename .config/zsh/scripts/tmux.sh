# Adds color and italics support for TMUX
[ -z "$TMUX" ] && export TERM=xterm-256color-italic
[ -z "$TMUX" ] && alias ssh="TERM=xterm-256color ssh"

