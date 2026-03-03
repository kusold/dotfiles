#!/usr/bin/env bash
# mintt - Minimal Tmux Theme
# Combines the best of minimal-tmux-status and tmux-dotbar

get_tmux_option() {
  local option="$1"
  local default="$2"
  local value
  value=$(tmux show-option -gqv "$option")
  echo "${value:-$default}"
}

# --- Colors ---
bg=$(get_tmux_option "@mintt-bg" "default")
fg=$(get_tmux_option "@mintt-fg" "default")
accent=$(get_tmux_option "@mintt-accent" "colour4")
fg_current=$(get_tmux_option "@mintt-fg-current" "colour0")
fg_session=$(get_tmux_option "@mintt-fg-session" "colour248")
fg_prefix=$(get_tmux_option "@mintt-fg-prefix" "colour0")
zoom_color=$(get_tmux_option "@mintt-zoom-color" "colour3")
bg_inactive=$(get_tmux_option "@mintt-bg-inactive" "colour238")

# --- Layout ---
position=$(get_tmux_option "@mintt-position" "bottom")
justify=$(get_tmux_option "@mintt-justify" "absolute-centre")

# --- Content Slots ---
show_left=$(get_tmux_option "@mintt-left" "true")
show_right=$(get_tmux_option "@mintt-right" "false")
status_left_override=$(get_tmux_option "@mintt-status-left" "")
status_right_override=$(get_tmux_option "@mintt-status-right" "")
status_left_extra=$(get_tmux_option "@mintt-status-left-extra" "")
status_right_extra=$(get_tmux_option "@mintt-status-right-extra" "")
right_text=$(get_tmux_option "@mintt-right-text" " %H:%M ")

# --- Smart Status-Right Toggles ---
right_time=$(get_tmux_option "@mintt-right-time" "true")
right_host=$(get_tmux_option "@mintt-right-host" "true")
right_battery=$(get_tmux_option "@mintt-right-battery" "true")
right_cpu=$(get_tmux_option "@mintt-right-cpu" "true")
right_min_width=$(get_tmux_option "@mintt-right-min-width" "200")
left_git=$(get_tmux_option "@mintt-left-git" "true")
left_min_width=$(get_tmux_option "@mintt-left-min-width" "200")

# --- Session ---
session_text=$(get_tmux_option "@mintt-session-text" " #S ")
session_position=$(get_tmux_option "@mintt-session-position" "left")

# --- Windows ---
window_format=$(get_tmux_option "@mintt-window-format" " #I:#W ")
window_separator=$(tmux show-option -gqv "@mintt-window-separator")
if [ -z "$window_separator" ] && ! tmux show-option -gq "@mintt-window-separator" | grep -q "@mintt-window-separator"; then
  window_separator="  "
fi
use_arrows=$(get_tmux_option "@mintt-use-arrows" "true")
left_arrow=$(get_tmux_option "@mintt-left-arrow" "")
right_arrow=$(get_tmux_option "@mintt-right-arrow" "")

# --- Bold ---
bold_status=$(get_tmux_option "@mintt-bold-status" "false")
bold_current=$(get_tmux_option "@mintt-bold-current" "false")

# --- Zoom ---
zoom_icon=$(get_tmux_option "@mintt-zoom-icon" "󰊓")
zoom_all_tabs=$(get_tmux_option "@mintt-zoom-all-tabs" "false")

# --- SSH ---
ssh_enabled=$(get_tmux_option "@mintt-ssh" "true")
ssh_icon=$(get_tmux_option "@mintt-ssh-icon" "󰌘")
ssh_icon_only=$(get_tmux_option "@mintt-ssh-icon-only" "false")
ssh_max_length=$(get_tmux_option "@mintt-ssh-max-length" "20")
ssh_min_width=$(get_tmux_option "@mintt-ssh-min-width" "60")

# --- Build bold attribute ---
bold_attr=""
if [ "$bold_status" = "true" ]; then
  bold_attr=",bold"
fi

current_bold=""
if [ "$bold_current" = "true" ]; then
  current_bold=",bold"
fi

# --- Build session component ---
# Normal state: fg_session on bg. Prefix state: fg_prefix on accent (bold).
session_component="#[bg=$bg,fg=$fg_session${bold_attr}]#{?client_prefix,,${session_text}}#[bg=$accent,fg=$fg_prefix,bold]#{?client_prefix,${session_text},}#[bg=$bg,fg=$fg_session,nobold]"

# --- Build time component ---
time_component="#[bg=$bg,fg=$fg${bold_attr}]${right_text}"

# --- Build smart status-right component ---
script_path="$HOME/.config/tmux/scripts/status-right.sh"
smart_right="#($script_path #{client_width} #{pane_current_path} $right_min_width $right_time $right_host $right_battery $right_cpu $ssh_min_width)"

# --- Build git branch component (left side) ---
git_script="$HOME/.config/tmux/scripts/git-branch.sh"
if [ "$left_git" = "true" ]; then
  git_component="#($git_script #{pane_current_path} #{client_width} $left_min_width)"
else
  git_component=""
fi

# --- Build status-left and status-right ---
if [ -n "$status_left_override" ]; then
  status_left="$status_left_override"
elif [ "$show_left" = "true" ]; then
  if [ "$session_position" = "left" ]; then
    status_left="${session_component}${git_component}${status_left_extra}"
  else
    status_left="${git_component}${status_left_extra}"
  fi
else
  status_left=""
fi

if [ -n "$status_right_override" ]; then
  status_right="$status_right_override"
elif [ "$show_right" = "true" ]; then
  if [ "$session_position" = "right" ]; then
    status_right="${status_right_extra}${smart_right}${session_component}"
  else
    status_right="${status_right_extra}${smart_right}"
  fi
else
  if [ "$session_position" = "right" ]; then
    status_right="${status_right_extra}${session_component}"
  else
    status_right="${status_right_extra}"
  fi
fi

# --- Build zoom suffix ---
zoom_suffix="#{?window_zoomed_flag, ${zoom_icon} ,}"

# --- Build SSH-aware window content ---
# When SSH is detected, show icon + hostname (truncated); otherwise show #W
if [ "$ssh_enabled" = "true" ]; then
  # Extract hostname from SSH command args via pane_pid
  # Uses a helper script to get the actual SSH hostname from the command line
  ssh_script="$HOME/.config/tmux/scripts/ssh-hostname.sh"
  ssh_hostname="#($ssh_script #{pane_pid} #{pane_current_command} $ssh_max_length)"
  if [ "$ssh_icon_only" = "true" ]; then
    ssh_display="${ssh_icon}"
  else
    ssh_display="${ssh_icon} ${ssh_hostname}"
  fi
  window_content="#{?#{==:#{pane_current_command},ssh},${ssh_display},#W}"
else
  window_content="#W"
fi

# Apply window_format: replace #W with our ssh-aware content
window_fmt="${window_format//#W/$window_content}"

# --- Build current window format ---
if [ "$use_arrows" = "true" ]; then
  current_window_fmt="#[fg=$accent,bg=$bg]${left_arrow}#[bg=$accent,fg=$fg_current${current_bold}]${window_fmt}${zoom_suffix}#[fg=$accent,bg=$bg]${right_arrow}"
else
  current_window_fmt="#[bg=$bg,fg=$accent${current_bold}]${window_fmt}${zoom_suffix}"
fi

# --- Build inactive window format ---
if [ "$zoom_all_tabs" = "true" ]; then
  inactive_zoom="${zoom_suffix}"
else
  inactive_zoom=""
fi
if [ "$use_arrows" = "true" ]; then
  inactive_window_fmt="#[fg=$bg_inactive,bg=$bg]${left_arrow}#[bg=$bg_inactive,fg=$fg${bold_attr}]${window_fmt}${inactive_zoom}#[fg=$bg_inactive,bg=$bg]${right_arrow}"
else
  inactive_window_fmt="#[bg=$bg,fg=$fg${bold_attr}]${window_fmt}${inactive_zoom}"
fi

# --- Apply settings ---
tmux set-option -g status-position "$position"
tmux set-option -g status-justify "$justify"
tmux set-option -g status-style "bg=$bg,fg=$fg"

tmux set-option -g status-left "$status_left"
tmux set-option -g status-right "$status_right"
tmux set-option -g status-left-length 200
tmux set-option -g status-right-length 200

tmux set-window-option -g window-status-format "$inactive_window_fmt"
tmux set-window-option -g window-status-current-format "$current_window_fmt"
tmux set-window-option -g window-status-separator "$window_separator"

# Clean up visual noise
tmux set-option -g status-left-style ""
tmux set-option -g status-right-style ""
tmux set-window-option -g window-status-style ""
tmux set-window-option -g window-status-current-style ""
tmux set-option -g message-style "bg=$bg,fg=$fg"
tmux set-option -g message-command-style "bg=$bg,fg=$fg"
