#!/usr/bin/env zsh
# Resume the coding-agent session (claude/codex/pi) that was running in a
# Rex terminal that Rex restored after a restart. The first shell in a
# new Rex block only lays down a marker; a later shell in the same block
# is a restored one. Logic and configuration:
# ~/.config/rex/agent-resume.sh (also: REX_AGENT_RESUME=0 disables).
if [[ -n "${REX_BLOCK:-}" && ${REX_AGENT_RESUME:-1} != 0 ]]; then
	"$HOME/.config/rex/ensure-recorder.sh"
	"$HOME/.config/rex/install-hooks.sh" --ensure

	_rex_resume_cmd="$("$HOME/.config/rex/agent-resume.sh")"
	if [[ -n "${_rex_resume_cmd}" ]]; then
		# Run once, just before the first prompt, so the rest of .zshrc
		# finishes first; exiting the agent returns to the prompt.
		_rex_resume_run() {
			precmd_functions=(${precmd_functions:#_rex_resume_run})
			local cmd="$_rex_resume_cmd"
			unset _rex_resume_cmd
			eval "$cmd"
		}
		precmd_functions+=(_rex_resume_run)
	else
		unset _rex_resume_cmd 2>/dev/null
	fi
fi
