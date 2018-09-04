#!/usr/bin/env zsh

_update_ruby_version() {
  typeset -g ruby_version=''
  if which rbenv &> /dev/null; then
    ruby_version="$(rbenv version | sed -e "s/ (set.*$//")"
  elif which rvm-prompt &> /dev/null; then
    ruby_version="$(rvm-prompt i v g)"
    rvm-prompt i v g
  else
    if which ruby &> /dev/null; then
      ruby_version="$(ruby --version | sed -e "s/ (set.*$//")"
    fi
  fi
}

_update_node_version() {
  typeset -g node_version=''
  if which nodenv &> /dev/null; then
    node_version="${${$(nodenv version)#v}[(w)0]}"
  elif which nvm &> /dev/null; then
    node_version="$(nvm current)"
  else
    if which node &> /dev/null; then
      node_version="$(node --version)"
    fi
  fi
}

#precmd() {
#  _update_ruby_version
#  _update_node_version
#  [[ ! -z ${ruby_version} ]] && PROMPT=" %F{1}ruby:${ruby_version}%f"
#  [[ ! -z ${node_version} ]] && PROMPT=" %F{2}node:${node_version}%f"
#}

