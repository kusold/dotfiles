#! /usr/bin/env bash

# Set the icon size of Dock items to 36 pixels
defaults write com.apple.dock tilesize -int 36

# Minimize windows into their application’s icon
defaults write com.apple.dock minimize-to-application -bool true

# Enable dock magnification
defaults write com.apple.dock magnification -bool true

# Set the magnification icon size of Dock items
defaults write com.apple.dock tilesize -int 75

# Set the dock to be on the right
defaults write com.apple.dock orientation -string right
