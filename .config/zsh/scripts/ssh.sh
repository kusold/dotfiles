#!/usr/bin/env zsh
autoload is_darwin

# This TERM is custom and will not be recognized by the remote server.
if [[ "$TERM" == "xterm-256color-italic" ]]; then
    alias ssh="TERM=xterm-256color ssh"
fi

# =============================================================================
# SSH Agent Socket Management
# Prefer forwarded agent, fall back to local
# =============================================================================

# Update the symlink to point to a working ssh agent socket
# Returns 0 if successful, 1 if failed
update_ssh_agent_symlink() {
  local new_sock="$1"

  if [[ -n "$new_sock" && -S "$new_sock" ]]; then
    # Test if socket actually works by trying to list keys
    if SSH_AUTH_SOCK="$new_sock" ssh-add -l >/dev/null 2>&1; then
      ln -sf "$new_sock" "$HOME/.ssh/ssh_auth_sock"
      export SSH_AUTH_SOCK="$HOME/.ssh/ssh_auth_sock"
      return 0
    fi
  fi
  return 1
}

# Start a local ssh-agent and update the symlink
# Use this when you want to use a local agent instead of forwarded one
start-local-ssh-agent() {
  # Start ssh-agent and capture its output
  eval "$(ssh-agent -s)" >/dev/null

  # Update the symlink to point to the new agent
  if update_ssh_agent_symlink "$SSH_AUTH_SOCK"; then
    echo "✓ Started local ssh-agent"
    echo "  Socket: $SSH_AUTH_SOCK"
    echo "  Symlink: $HOME/.ssh/ssh_auth_sock"
  else
    echo "✗ Failed to start ssh-agent" >&2
    return 1
  fi
}

# Main SSH agent initialization logic
init_ssh_agent() {
  if [[ -n "$SSH_CLIENT" ]]; then
    # Remote session - prefer forwarded agent
    if ! update_ssh_agent_symlink "$SSH_AUTH_SOCK"; then
      # Forwarded socket doesn't work, try existing symlink
      if [[ -S "$HOME/.ssh/ssh_auth_sock" ]]; then
        # Resolve symlink to its actual target
        local existing_sock="$(readlink "$HOME/.ssh/ssh_auth_sock")"
        if [[ -n "$existing_sock" && -S "$existing_sock" ]]; then
          if update_ssh_agent_symlink "$existing_sock"; then
            return
          fi
        fi
      fi

      # Start new local agent as fallback
      start-local-ssh-agent
    fi
  else
    # Local session - ensure symlink points to a working socket
    if [[ -n "$SSH_AUTH_SOCK" ]]; then
      # If SSH_AUTH_SOCK is already our symlink, resolve it to check if it's valid
      if [[ "$SSH_AUTH_SOCK" == "$HOME/.ssh/ssh_auth_sock" ]]; then
        if [[ -L "$HOME/.ssh/ssh_auth_sock" ]]; then
          local target="$(readlink "$HOME/.ssh/ssh_auth_sock")"
          # Check if symlink is circular or points to non-existent socket
          if [[ "$target" == "$HOME/.ssh/ssh_auth_sock" ]] || [[ ! -S "$target" ]]; then
            # Broken symlink - find real socket or unset to trigger fallback
            unset SSH_AUTH_SOCK
          fi
        fi
      fi

      # If we have a valid socket (not our symlink), create/update the symlink
      if [[ -n "$SSH_AUTH_SOCK" && "$SSH_AUTH_SOCK" != "$HOME/.ssh/ssh_auth_sock" ]]; then
        ln -sf "$SSH_AUTH_SOCK" "$HOME/.ssh/ssh_auth_sock"
        export SSH_AUTH_SOCK="$HOME/.ssh/ssh_auth_sock"
      fi
    fi
  fi
}

# Initialize on shell startup
init_ssh_agent

# =============================================================================
# Platform-specific key loading
# =============================================================================

if is_darwin && [[ -z "$(ssh-add -l 2>/dev/null)" ]]; then
    ssh-add --apple-load-keychain
fi
