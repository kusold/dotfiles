#!/bin/sh
# Self-report hook for claude and codex, installed into their hook
# configs by ~/.config/rex/install-hooks.sh. The agent runs it on
# SessionStart with a JSON payload on stdin; it records which
# conversation belongs to this Rex block, so a restored terminal resumes
# the exact session that ran in it. Invoked as:
#   bash ~/.config/rex/hooks/rex-agent-state.sh claude
#   bash ~/.config/rex/hooks/rex-agent-state.sh codex
# Never fails and never blocks the agent.

# REX_AGENT_RESUME_HOOK_VERSION=1

agent="$1"
[ "$agent" = claude ] || [ "$agent" = codex ] || exit 0
[ -n "${REX_BLOCK:-}" ] || exit 0
[ "${REX_AGENT_RESUME:-1}" = "0" ] && exit 0

input=$(cat 2>/dev/null)

field() {
    printf '%s' "$input" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
        | head -1 | sed 's/.*"\([^"]*\)"$/\1/'
}

[ "$(field hook_event_name)" = "SessionStart" ] || exit 0
session=$(field session_id)
[ -n "$session" ] || exit 0

# Codex exports the owning thread; a report that belongs to a different
# one (nested/subagent) is not this pane's conversation.
if [ "$agent" = codex ] && [ -n "${CODEX_THREAD_ID:-}" ] \
    && [ "$CODEX_THREAD_ID" != "$session" ]; then
    exit 0
fi

cache="${XDG_CACHE_HOME:-$HOME/.cache}/rex-agent-resume"
mkdir -p "$cache" 2>/dev/null || exit 0
sessions="$cache/sessions.tsv"
lock="$cache/.sessions.lock"

# Short lock; on contention give up (another report for another block
# will land soon enough from its own hook run).
i=0
while ! mkdir "$lock" 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -lt 20 ] || exit 0
    sleep 0.05 2>/dev/null || sleep 1
done
trap 'rmdir "$lock" 2>/dev/null' EXIT

tmp="$sessions.tmp"
{
    awk -F'\t' -v b="$REX_BLOCK" '$1 != b' "$sessions" 2>/dev/null
    printf '%s\t%s\t%s\t%s\n' "$REX_BLOCK" "$agent" "$session" "$(date +%s)"
} >"$tmp" && mv "$tmp" "$sessions"

exit 0
