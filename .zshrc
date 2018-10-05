# Set default text editor
export VISUAL=vim
export EDITOR="$VISUAL"

# Source functions
fpath=($DOTFILES/zsh/functions $fpath)

# Source all utilities
for script in $DOTFILES/zsh/utilities/*.sh; do
  if [ -x "${script}" ]; then
    source ${script}
  fi
done

# Source all scripts
for script in $DOTFILES/zsh/scripts/*.sh; do
  if [ -x "${script}" ]; then
    source ${script}
  fi
done

# Source zplug and plugins
if [[ -d "$HOME/.zplug" ]]; then
  export ZPLUG_HOME=$HOME/.zplug
  source "$ZPLUG_HOME/init.zsh"
  source "$DOTFILES/zsh/zplugins.zsh"
fi

# Development Directory Shortcut
#if [[ -d "$HOME/Development" ]]; then
#  alias -g dev=$HOME/Development/
#fi

# Use Custom Key Map (Map L Ctrl -> Capslock. Map Capslock -> R Menu)
if [ -f $HOME/.Xmodmap ]; then
  /usr/bin/xmodmap $HOME/.Xmodmap
fi

# CertCanary Go Directory
if [[ -d "$GOPATH/src/gitlab.com/certcanary" ]]; then
  hash -d canary=$GOPATH/src/gitlab.com/certcanary/
  alias -g gocc=$GOPATH/src/gitlab.com/certcanary
fi

# My Github Go Directory
if [[ -d "$GOPATH/src/github.com/kusold" ]]; then
  alias -g gome=$GOPATH/src/github.com/kusold
fi

# Increase the maximum open files. This is useful for filewatcher programs (such as node-dev)
#ulimit -n 10000

## Aliases ##
#alias myip="ifconfig | grep '^[a-z0-1]*:' | cut '-d:' -f1 | xargs -I {} ipconfig getifaddr {}"
alias myip="curl https://icanhazip.com"
alias weather="~/dotfiles/ansiweather/ansiweather"
alias ssh-keygen-strong='ssh-keygen -t rsa -b 4096 -C "$(whoami)@$(hostname)-$(date +%Y-%m-%dT%H:%M:%S%z)" -f "$HOME/.ssh/$(whoami)@$(hostname)-$(date +%Y-%m-%dT%H:%M:%S%z)"'
alias backup-to-nas='rsync --archive --delete --progress --exclude-from="$HOME/dotfiles/rsync_exclude.txt" --verbose $HOME/ admin@coruscant:/share/Backups/$HOST'

# Load private environment files
if [ -f $HOME/.env.private ]; then
  source $HOME/.env.private
fi

# Use gpg-agent instead of ssh-agent if it is configured
if [ -f "${HOME}/.gpg-agent-info" ]; then
  . "${HOME}/.gpg-agent-info"
  export GPG_AGENT_INFO
  export SSH_AUTH_SOCK
fi
export GPG_TTY=$(tty)

# Always set the ssh agent in the same place
if [[ ! -z $SSH_AUTH_SOCK &&  "$SSH_AUTH_SOCK" != "$HOME/.ssh/ssh_auth_sock" ]]; then
  ln -sf "$SSH_AUTH_SOCK" "$HOME/.ssh/ssh_auth_sock"
  export SSH_AUTH_SOCK="$HOME/.ssh/ssh_auth_sock"
fi


[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# Emacs tramp fix
if [[ "$TERM" == "dumb" ]]
then
  unsetopt zle
  unsetopt prompt_cr
  unsetopt prompt_subst
  unfunction precmd
  unfunction preexec
  PS1='$ '
fi
