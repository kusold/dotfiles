#!/usr/bin/env zsh
# Makes working with docker easier
autoload command_exists

if command_exists docker; then
  # Kill all running containers.
  alias dockerkillall='docker kill $(docker ps -q)'
  # Delete all stopped containers.
  alias dockercleanc='printf "\n>>> Deleting stopped containers\n\n" && docker rm $(docker ps -a -q)'
  # Delete all untagged images.
  alias dockercleani='printf "\n>>> Deleting untagged images\n\n" && docker rmi $(docker images -q -f dangling=true)'
  # Delete all stopped containers and untagged images.
  alias dockerclean='dockercleanc || true && dockercleani'
fi

