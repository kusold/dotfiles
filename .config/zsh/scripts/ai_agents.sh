#!/usr/bin/env zsh
autoload command_exists;

if command_exists claude; then
  alias claude-yolo='claude --dangerously-skip-permissions'
fi
if command_exists codex; then
  alias codex-yolo='codex --yolo'
fi
if command_exists kiro-cli; then
  alias kiro-yolo='kiro-cli chat --trust-all-tools --trust-workspace'
fi
