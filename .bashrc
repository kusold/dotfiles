[ -f ~/.fzf.bash ] && source ~/.fzf.bash

# Added by LM Studio CLI (lms)
export PATH="$PATH:$HOME/.lmstudio/bin"
# End of LM Studio CLI section

. "$HOME/.cargo/env"

# Resume the coding-agent session (claude/codex/pi) that was running in a
# Rex terminal that Rex restored after a restart. See
# ~/.config/rex/agent-resume.sh for how it decides (REX_AGENT_RESUME=0
# disables).
if [ -n "${REX_BLOCK:-}" ] && [ "${REX_AGENT_RESUME:-1}" != "0" ]; then
    "$HOME/.config/rex/ensure-recorder.sh"
    "$HOME/.config/rex/install-hooks.sh" --ensure
    _rex_resume_cmd="$("$HOME/.config/rex/agent-resume.sh")"
    [ -z "$_rex_resume_cmd" ] || eval "$_rex_resume_cmd"
    unset _rex_resume_cmd
fi
