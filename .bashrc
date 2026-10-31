[ -f ~/.fzf.bash ] && source ~/.fzf.bash

. "$HOME/.cargo/env"

# Bootstrap the Rex agent-resume recorder (see ~/.config/rex/recorder.lua).
if [ -n "${REX_BLOCK:-}" ] && [ "${REX_AGENT_RESUME:-1}" != "0" ]; then
    "$HOME/.config/rex/ensure-recorder.sh"
fi
