#!/usr/bin/env bash
# mintt - Smart conditional status-right
# Called via #() from tmux status-right
#
# Args: client_width pane_path min_width time_on host_on battery_on cpu_on

client_width="${1:-0}"
pane_path="${2:-$HOME}"
min_width="${3:-200}"
time_on="${4:-true}"
host_on="${5:-true}"
battery_on="${6:-true}"
cpu_on="${7:-true}"

# Colors (matching theme palette)
dim="colour240"
text="colour248"
icon_color="colour4"

divider="#[fg=$dim] │ #[fg=$text]"
items=()

# --- CPU Load ---
if [ "$cpu_on" = "true" ]; then
  if command -v sysctl &>/dev/null; then
    # macOS
    cpu=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')
  elif [ -f /proc/loadavg ]; then
    # Linux
    cpu=$(awk '{print $1}' /proc/loadavg)
  fi
  if [ -n "$cpu" ]; then
    items+=("#[fg=$icon_color]󰍛 #[fg=$text]$cpu")
  fi
fi

# --- Battery ---
if [ "$battery_on" = "true" ]; then
  pct=""
  charging=""
  if command -v pmset &>/dev/null; then
    # macOS
    batt_info=$(pmset -g batt 2>/dev/null)
    pct=$(echo "$batt_info" | grep -oE '[0-9]+%' | head -1 | tr -d '%')
    if echo "$batt_info" | grep -q 'AC Power'; then
      charging="yes"
    fi
  elif [ -d /sys/class/power_supply/BAT0 ]; then
    # Linux
    pct=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null)
    status=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null)
    if [ "$status" = "Charging" ] || [ "$status" = "Full" ]; then
      charging="yes"
    fi
  fi
  if [ -n "$pct" ]; then
    if [ "$charging" = "yes" ]; then
      icon="󰂄"
    elif [ "$pct" -ge 90 ]; then
      icon="󰁹"
    elif [ "$pct" -ge 80 ]; then
      icon="󰂂"
    elif [ "$pct" -ge 70 ]; then
      icon="󰂁"
    elif [ "$pct" -ge 60 ]; then
      icon="󰂀"
    elif [ "$pct" -ge 50 ]; then
      icon="󰁿"
    elif [ "$pct" -ge 40 ]; then
      icon="󰁾"
    elif [ "$pct" -ge 30 ]; then
      icon="󰁽"
    elif [ "$pct" -ge 20 ]; then
      icon="󰁼"
    elif [ "$pct" -ge 10 ]; then
      icon="󰁻"
    else
      icon="󰂎"
    fi
    items+=("#[fg=$icon_color]$icon #[fg=$text]${pct}%%")
  fi
fi

# --- Host/User (SSH only, width-gated) ---
if [ "$host_on" = "true" ] && [ "$client_width" -ge "$min_width" ] 2>/dev/null; then
  if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ] || [ -n "$SSH_CONNECTION" ]; then
    host=$(hostname -s 2>/dev/null || echo "$HOSTNAME")
    items+=("#[fg=$icon_color]󰌘 #[fg=$text]$USER@$host")
  fi
fi

# --- Date/Time (width-gated) ---
if [ "$time_on" = "true" ] && [ "$client_width" -ge "$min_width" ] 2>/dev/null; then
  items+=("#[fg=$icon_color] #[fg=$text]$(date '+%H:%M')")
fi

# --- Assemble output ---
result=""
for i in "${!items[@]}"; do
  if [ "$i" -gt 0 ]; then
    result+="$divider"
  fi
  result+="${items[$i]}"
done

if [ -n "$result" ]; then
  echo " $result "
fi
