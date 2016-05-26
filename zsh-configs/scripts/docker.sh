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
  # Delete orphaned volumes
  alias dockercleanv='printf "\n>>> Deleting orphaned volumes\n\n" && docker volume rm $(docker volume ls -qf dangling=true)'
  # Delete all stopped containers and untagged images.
  alias dockerclean='dockercleanc || true && dockercleani || true && dockercleanv'
fi

