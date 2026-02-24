#!/usr/bin/env zsh

export XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-"${HOME}/.config"}
export XDG_CACHE_HOME=${XDG_CACHE_HOME:-"${HOME}/.cache"}
export XDG_DATA_HOME=${XDG_DATA_HOME:-"${HOME}/.local/share"}
export XDG_STATE_HOME=${XDG_STATE_HOME:-"${HOME}/.local/state"}
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-"${TMPDIR}"}

###
# Ruby
###
export BUNDLE_USER_CACHE=$XDG_CACHE_HOME/bundle
export BUNDLE_USER_CONFIG=$XDG_CONFIG_HOME/bundle/config
export BUNDLE_USER_PLUGIN=$XDG_DATA_HOME/bundle
