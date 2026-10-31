#!/usr/bin/env zsh
# Bootstrap for the Rex agent-resume recorder. The resume itself runs on
# the Rex side (recorder.lua); this only guarantees the recorder process
# comes back after a restart, because restored terminals always spawn a
# shell. REX_AGENT_RESUME=0 disables the whole system.
if [[ -n "${REX_BLOCK:-}" && ${REX_AGENT_RESUME:-1} != 0 ]]; then
	"$HOME/.config/rex/ensure-recorder.sh"
fi
