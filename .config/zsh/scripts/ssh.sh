#!/usr/bin/env zsh
autoload is_darwin

# This TERM is custom and will not be recognized by the remote server.
if [[ "$TERM" == "xterm-256color-italic" ]]; then
    alias ssh="TERM=xterm-256color ssh"
fi

# Always set the ssh agent in the same place
if [[ ! -z $SSH_AUTH_SOCK &&  "$SSH_AUTH_SOCK" != "$HOME/.ssh/ssh_auth_sock" ]]; then
  ln -sf "$SSH_AUTH_SOCK" "$HOME/.ssh/ssh_auth_sock"
  export SSH_AUTH_SOCK="$HOME/.ssh/ssh_auth_sock"
fi

if [[ is_darwin && -z "$(ssh-add -l 2>/dev/null)" ]]; then
    ssh-add --apple-load-keychain
fi
