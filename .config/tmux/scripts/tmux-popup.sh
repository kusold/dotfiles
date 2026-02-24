#!/bin/bash
# Dismissable popup shell using a hidden per-session tmux session.
# Based on https://willhbr.net/2023/02/07/dismissable-popup-shell-in-tmux/

session="$(tmux display -p '_popup_#S')"

if ! tmux has -t "$session" 2>/dev/null; then
  parent_session="$(tmux display -p '#{session_id}')"
  session_id="$(tmux new-session -c '#{pane_current_path}' -dP -s "$session" -F '#{session_id}' -e TMUX_PARENT_SESSION="$parent_session")"
  exec tmux set-option -t "$session_id" status off \; \
    attach -t "$session"
fi

exec tmux attach -t "$session" >/dev/null
