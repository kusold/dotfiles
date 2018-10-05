
################################################################################
# Directory of ZSH Plugins                                                     #
# https://github.com/unixorn/awesome-zsh-plugins                               #
#                                                                              #
# zplug documentation                                                          #
# https://github.com/zplug/zplug                                               #
################################################################################

#
# Completions
#
zplug "webyneter/docker-aliases", use:docker-aliases.plugin.zsh
zplug "zsh-users/zsh-completions", depth:1

#
# Plugins
#

# Syntax highlighting
zplug "zsh-users/zsh-syntax-highlighting", defer:2
# Type command from history and then use the arrow keys to cylce through
zplug "zsh-users/zsh-history-substring-search", defer:3

zplug "zsh-users/zsh-autosuggestions"
zplug "chrissicool/zsh-256color", use:zsh-256color.plugin.zsh
zplug "supercrabtree/k"

# A Zsh plugin to help remembering those shell aliases and Git aliases you once defined.
zplug "djui/alias-tips"

# Make working with colors easier
zplug "modules/spectrum", from:prezto

#
# Theme
#

# Async for zsh, used by pure
zplug "mafredri/zsh-async", from:github, defer:0
zplug "sindresorhus/pure", use:pure.zsh, from:github, as:theme

BASE16_SCHEME="eighties"
zplug "chriskempson/base16-shell", use:"base16-shell.plugin.zsh", defer:0
zplug "chriskempson/base16-shell", use:"scripts/base16-$BASE16_SCHEME.sh", defer:0
zplug "chriskempson/base16-shell", use:colortest, as:command

zplug "fcambus/ansiweather", as:command

#
# Load everything up
#

# Install plugins if there are plugins that have not been installed
if ! zplug check --verbose; then
  printf "New ZSH plugins are waiting to be installed.\nInstall? [y/N]: "
  if read -q; then
    echo; zplug install
  fi
fi

# Source plugin configurations
for script in $DOTFILES/zsh/plugins/*.zsh; do
  if [ -x "${script}" ]; then
    source ${script}
  fi
done

zplug load

