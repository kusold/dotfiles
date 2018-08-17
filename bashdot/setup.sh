#! /usr/bin/env bash

# TODO: Create utility to allow spaces in config arrays without escaping

BASHDOT_DIR="${BASH_SOURCE%/*}"
if [[ ! -d "$BASHDOT_DIR" ]]; then BASHDOT_DIR="$PWD"; fi

# load an easy way to set colors
source $BASHDOT_DIR/colors.sh;
source $BASHDOT_DIR/utilities/logger.sh;

# load config
source $BASHDOT_DIR/config.sh

# load utilities
for script in $BASHDOT_DIR/utilities/*.sh; do
  if [ -x "${script}" ]; then
    source ${script}
  fi
done

# print banner
source $BASHDOT_DIR/banner.sh

# install cli utilities
# if osx
# if command does not exist then install homebrew
log_module "Installing homebrew modules\n"
source $BASHDOT_DIR/modules/homebrew.sh;
homebrew_install_packages "${homebrew_present[@]}";

log_module "Updating git submodules"
