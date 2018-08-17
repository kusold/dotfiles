#! /usr/bin/env bash

homebrew_install_packages() {
  local pkgs=("$@")
  local params=()

  # Disable auto-updates
  HOMEBREW_NO_AUTO_UPDATE=1

  params=( "homebrew_update" "Updating homebrew repository")
  run_task "${params[@]}";

  for pkg in "${pkgs[@]}"; do
    params=( "homebrew_install_pkg $pkg" "Installing ${pkg}" )
    run_task "${params[@]}";
  done
}

homebrew_update() {
  local output=$(brew update 2>&1)
  local retval=$?

  case $output in
    "Already up-to-date"*)
      echo $STATUS_NOT_MODIFIED;
      ;;
    "Updated"*)
      echo $STATUS_MODIFIED;
      ;;
    *)
      echo $STATUS_ERROR;
      ;;
  esac
  return $retval
}

homebrew_upgrade() {
  local output=$(brew upgrade 2>&1)
  local retval=$?

  if [ $retval -eq 0 ]; then
    if [ $output -eq "" ]; then
      echo $STATUS_NOT_MODIFIED;
    else
      echo $STATUS_MODIFIED;
    fi
  else
      echo $STATUS_ERROR;
  fi
  return $retval
}

homebrew_install_pkg() {
  local pkg=$1;

  local output=$(brew install $pkg 2>&1)
  local retval=$?

  case $output in
    *"brew reinstall"*)
      echo $STATUS_NOT_MODIFIED;
      ;;
    *"Downloading"*)
      echo $STATUS_MODIFIED;
      ;;
    *"brew upgrade"*)
      echo $STATUS_MODIFIED;
      ;;
    *)
      echo $STATUS_ERROR;
      ;;
  esac
  return $retval
}

