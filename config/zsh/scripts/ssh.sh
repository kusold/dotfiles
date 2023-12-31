# This TERM is custom and will not be recognized by the remote server.
if [[ "$TERM" == "xterm-256color-italic" ]]; then
    alias ssh="TERM=xterm-256color ssh"
fi
