#!/usr/bin/env zsh
autoload is_darwin

if is_darwin; then
  # Make finder display hidden files
  alias showFiles='defaults write com.apple.finder AppleShowAllFiles YES; killall Finder /System/Library/CoreServices/Finder.app'
  # Make finder not display hidden files
  alias hideFiles='defaults write com.apple.finder AppleShowAllFiles NO;  killall Finder /System/Library/CoreServices/Finder.app'
fi

