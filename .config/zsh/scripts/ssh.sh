#!/usr/bin/env zsh

# =============================================================================
# SSH Agent Socket Management (DRY version)
#
# This script configures SSH agent support by breaking logic into core
# reusable functions.
# =============================================================================

# Define the well-known socket path for tmux and other processes
TMUX_SSH_AUTH_SOCK="$HOME/.ssh/ssh_auth_sock"

# =============================================================================
# Core SSH Agent Logic (Internal Functions)
# =============================================================================

# (Internal) Tries to find a working agent or starts a new one.
# Exports SSH_AUTH_SOCK with the real socket path on success.
# Returns 0 on success, 1 on failure.
_ssh_agent_find_or_start() {
    # 1. If we already have a working agent in this shell, do nothing.
    if [ -n "$SSH_AUTH_SOCK" ] && ssh-add -l >/dev/null 2>&1; then
        return 0
    fi

    # 2. Unset any stale socket and try to find a working one via the symlink.
    unset SSH_AUTH_SOCK
    if [ -L "$TMUX_SSH_AUTH_SOCK" ]; then
        local REAL_SOCK
        REAL_SOCK=$(readlink -f "$TMUX_SSH_AUTH_SOCK")
        if [ -S "$REAL_SOCK" ]; then
            export SSH_AUTH_SOCK="$REAL_SOCK"
            # Test if the agent is responsive.
            if ssh-add -l >/dev/null 2>&1; then
                # Found a working agent via the symlink.
                return 0
            fi
        fi
    fi

    # 3. If still no working agent, start a new one.
    unset SSH_AUTH_SOCK
    eval "$(ssh-agent -s)" >/dev/null
    if [ -z "$SSH_AUTH_SOCK" ]; then
        # Agent failed to start.
        return 1
    fi
    return 0
}

# (Internal) Updates the symlink to point to the current SSH_AUTH_SOCK
_ssh_agent_update_symlink() {
    if [ -S "$SSH_AUTH_SOCK" ]; then
        # Only update if the symlink doesn't already point to the right place
        if [ ! -L "$TMUX_SSH_AUTH_SOCK" ] || [ "$(readlink -f "$TMUX_SSH_AUTH_SOCK")" != "$SSH_AUTH_SOCK" ]; then
          ln -sf "$SSH_AUTH_SOCK" "$TMUX_SSH_AUTH_SOCK"
        fi
        return 0
    fi
    return 1
}

# =============================================================================
# Automatic Initialization Logic (on shell startup)
# =============================================================================

_ssh_agent_auto_init() {
    local ACTIVE_SOCK=""

    # --- Method 1: Managed Agent (systemd / home-manager) ---
    if [ -n "$XDG_RUNTIME_DIR" ]; then
        local HM_SSH_SOCK="$XDG_RUNTIME_DIR/ssh-agent"
        local SYSTEMD_SSH_SOCK="$XDG_RUNTIME_DIR/keyring/ssh"
        if [ -S "$HM_SSH_SOCK" ]; then ACTIVE_SOCK="$HM_SSH_SOCK";
        elif [ -S "$SYSTEMD_SSH_SOCK" ]; then ACTIVE_SOCK="$SYSTEMD_SSH_SOCK";
        fi
    fi

    if [ -n "$ACTIVE_SOCK" ]; then
        export SSH_AUTH_SOCK="$ACTIVE_SOCK"
    # --- Method 2: Forwarded Agent ---
    elif [ -n "$SSH_CLIENT" ] && [ -n "$SSH_AUTH_SOCK" ] && [ -S "$SSH_AUTH_SOCK" ]; then
        # A forwarded agent is active. The variable is already set.
        : # Do nothing.
    # --- Method 3: Fallback (find or start local) ---
    else
        _ssh_agent_find_or_start
    fi

    # Finally, always update the symlink based on the decided-upon socket.
    _ssh_agent_update_symlink
}

# Run the auto-initialization for the shell session.
_ssh_agent_auto_init

# =============================================================================
# User-facing Helper Function
# =============================================================================

ssh_agent_start() {
  echo "Checking SSH agent status..."
  if _ssh_agent_find_or_start; then
      if _ssh_agent_update_symlink; then
          echo "✓ SSH Agent is running and symlink is up to date."
          echo "  Socket: $SSH_AUTH_SOCK"
      else
          echo "✗ Agent is running, but failed to update symlink." >&2
      fi
  else
      echo "✗ Failed to find or start an SSH Agent." >&2
  fi
}
alias ssh-agent-start="ssh_agent_start"


# =============================================================================
# Platform-specific additions
# =============================================================================

# Alias ssh to set a compatible TERM on remote servers
if [[ "$TERM" == "xterm-256color-italic" ]]; then
    alias ssh="TERM=xterm-256color ssh"
fi

# On macOS, load keys from keychain if no keys are loaded
autoload is_darwin
if is_darwin && [[ -z "$(ssh-add -l 2>/dev/null)" ]]; then
    ssh-add --apple-load-keychain
fi
