# Adds color and italics support for TMUX
[ -z "$TMUX+x" ] && export TERM=xterm-256color-italic
[ -z "$TMUX+x" ] && alias ssh="TERM=xterm-256color ssh"

