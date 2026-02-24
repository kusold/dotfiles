#!/usr/bin/env bash
# mintt - Git branch for status-left
# Called via #() from tmux status-left
#
# Args: pane_current_path

pane_path="${1:-$HOME}"

if [ ! -d "$pane_path" ]; then
  exit 0
fi

branch=$(git -C "$pane_path" symbolic-ref --short HEAD 2>/dev/null)
if [ -z "$branch" ]; then
  branch=$(git -C "$pane_path" rev-parse --short HEAD 2>/dev/null)
fi

if [ -n "$branch" ]; then
  echo "#[fg=colour4]󰘬 #[fg=colour248]$branch "
fi
