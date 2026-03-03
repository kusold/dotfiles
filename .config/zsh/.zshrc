# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.config/zsh/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# load zprof first if we need to profile
[[ ${ZPROFILE:-0} -eq 0 ]] || zmodload zsh/zprof
alias zprofile="ZPROFILE=1 zsh"

# Source functions
fpath=($ZDOTDIR/functions $fpath)

# Source all utilities
for script in $ZDOTDIR/utilities/*.sh; do
  if [ -x "${script}" ]; then
    source ${script}
  fi
done

# Source prescripts (must run before antidote load)
for script in $ZDOTDIR/prescripts/*.sh; do
  if [ -x "${script}" ]; then
    source ${script}
  fi
done

# Install antidote if it is not found
[[ -f $ZDOTDIR/.antidote/antidote.zsh ]] || git clone --depth=1 https://github.com/mattmc3/antidote.git ${ZDOTDIR:-~}/.antidote

source ${ZDOTDIR}/.antidote/antidote.zsh
zstyle ':antidote:bundle' use-friendly-names 'yes'

# Source plugin configurations
for script in $DOTFILES/zsh/plugins/*.zsh; do
  if [ -x "${script}" ]; then
    source ${script}
  fi
done

antidote load

# Source all scripts (after antidote, so zsh-defer is available)
for script in $ZDOTDIR/scripts/*.sh; do
  if [ -x "${script}" ]; then
    source ${script}
  fi
done

# Override zephyr's matcher-list to add boundary matching on . _ -
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'

# Run bashcompinit after zephyr's deferred compinit
function _run_bashcompinit { autoload -Uz bashcompinit && bashcompinit }
post_zshrc_hook+=(_run_bashcompinit)

alias zsh-completions-regen='rm -f ${ZSH_COMPDUMP} && exec zsh'



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
alias ssh-keygen-strong-rsa='ssh-keygen -t rsa -b 4096 -C "$(whoami)@$(hostname)-$(date +%Y-%m-%dT%H:%M:%S%z)" -f "$HOME/.ssh/$(whoami)@$(hostname)-$(date +%Y-%m-%dT%H:%M:%S%z)"'
alias ssh-keygen-strong='ssh-keygen -t ed25519 -C "$(whoami)@$(hostname)-$(date +%Y-%m-%dT%H:%M:%S%z)" -f "$HOME/.ssh/$(whoami)@$(hostname)-$(date +%Y-%m-%dT%H:%M:%S%z)"'
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

# SSH agent socket management is now handled in scripts/ssh.sh



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


[[ ${ZPROFILE:-0} -eq 0 ]] || { unset ZPROFILE && zprof }

# To customize prompt, run `p10k configure` or edit ~/.config/zsh/.p10k.zsh.
[[ ! -f ~/.config/zsh/.p10k.zsh ]] || source ~/.config/zsh/.p10k.zsh

# Re-source p10k config when terminal width crosses the narrow/wide threshold
# (e.g., attaching to tmux from a phone vs desktop).
_p10k_responsive_last=$COLUMNS
TRAPWINCH() {
  local threshold=60
  if (( (COLUMNS < threshold) != (_p10k_responsive_last < threshold) )); then
    [[ -f ~/.config/zsh/.p10k.zsh ]] && source ~/.config/zsh/.p10k.zsh
  fi
  _p10k_responsive_last=$COLUMNS
}
