export DOTFILES="$HOME/.config"

#
# Defines environment variables.
#
# Authors:
#   Sorin Ionescu <sorin.ionescu@gmail.com>
#

#
# Browser
#

if [[ "$OSTYPE" == darwin* ]]; then
  export BROWSER='open'
fi
#
#
# Language
#

export LANG="${LANG:-en_US.UTF-8}"
export LANG="${LANGUAGE:-en}"
export LANG="${LC_ALL:-en_US.UTF-8}"

#
# Editors
#

export EDITOR='nvim'
export VISUAL='code'
export PAGER='less'


#
# Paths
#

typeset -gU cdpath fpath mailpath path

# Set the the list of directories that cd searches.
# cdpath=(
#   $cdpath
# )

# Set the list of directories that Zsh searches for programs.
path=(
  $path
  /usr/local/{bin,sbin}
)

#
# Temporary Files
#

if [[ ! -d "$TMPDIR" ]]; then
  export TMPDIR="/tmp/$USER"
  mkdir -p -m 700 "$TMPDIR"
fi

TMPPREFIX="${TMPDIR%/}/zsh"
if [[ ! -d "$TMPPREFIX" ]]; then
  mkdir -p "$TMPPREFIX"
fi

# Source all envs
for script in $ZDOTDIR/env/*.sh; do
  if [ -x "${script}" ]; then
    source ${script}
  fi
done

