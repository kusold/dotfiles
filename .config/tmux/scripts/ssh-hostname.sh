#!/usr/bin/env bash
# Extract hostname from SSH command line
# Usage: ssh-hostname.sh <pane_pid> <current_command> <max_length>

pane_pid="$1"
current_command="$2"
max_length="${3:-20}"

# Only process if current command is ssh
if [ "$current_command" != "ssh" ]; then
  echo ""
  exit 0
fi

# Get the command line of the ssh process
# Walk up the process tree to find ssh command with arguments
ssh_cmdline=""

# Try to get the command line from the pane's child processes
# pgrep finds child processes of the pane_pid
for pid in $(pgrep -P "$pane_pid" 2>/dev/null); do
  comm=$(ps -p "$pid" -o comm= 2>/dev/null | tr -d ' ')
  if [ "$comm" = "ssh" ]; then
    ssh_cmdline=$(ps -p "$pid" -o args= 2>/dev/null)
    break
  fi
  # Also check nested processes (e.g., ssh inside shell)
  for child_pid in $(pgrep -P "$pid" 2>/dev/null); do
    comm=$(ps -p "$child_pid" -o comm= 2>/dev/null | tr -d ' ')
    if [ "$comm" = "ssh" ]; then
      ssh_cmdline=$(ps -p "$child_pid" -o args= 2>/dev/null)
      break 2
    fi
  done
done

# If no ssh process found via pgrep, try lsof on the tty
if [ -z "$ssh_cmdline" ]; then
  # Fallback: look for ssh in recent process list
  ssh_cmdline=$(ps -eo pid,ppid,args | awk -v ppid="$pane_pid" '$2 == ppid && /ssh/ && !/awk/ {print substr($0, index($0, $3)); exit}')
fi

if [ -z "$ssh_cmdline" ]; then
  echo ""
  exit 0
fi

# Parse hostname from SSH command
# Common formats:
#   ssh user@host
#   ssh -p port user@host
#   ssh -i keyfile user@host
#   ssh host (uses default user)
#   ssh -L local:remote host

hostname=""

# Remove leading ssh command
args="${ssh_cmdline#ssh }"

# Process arguments
while [ -n "$args" ]; do
  # Get first word
  word="${args%% *}"

  # Skip if empty
  if [ -z "$word" ]; then
    args="${args# }"
    continue
  fi

  # Skip flags (start with -)
  if [[ "$word" == -* ]]; then
    # Check if this flag takes an argument
    case "$word" in
      -i|-F|-l|-p|-L|-R|-D|-S|-W|-w)
        # Next word is the flag's argument, skip it
        args="${args#* }"
        ;;
      -o|-J|-Q|-N|-n|-T|-t|-v|-q|-V|-X|-x|-Y|-y|-g|-4|-6|-A|-a|-C|-f|-n|-s)
        # These flags don't take arguments or are handled differently
        ;;
      *)
        # Check for combined short flags like -p2222
        if [[ "$word" =~ ^-[pfilLRS] ]]; then
          : # Flag with inline argument, skip
        fi
        ;;
    esac
    args="${args#* }"
    continue
  fi

  # This should be the hostname (possibly with user@)
  hostname="$word"
  break
done

# Extract just the hostname if it's user@host format
if [[ "$hostname" == *@* ]]; then
  hostname="${hostname#*@}"
fi

# Truncate if needed
if [ ${#hostname} -gt "$max_length" ]; then
  hostname="${hostname:0:$max_length}…"
fi

echo "$hostname"
