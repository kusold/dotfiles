#!/bin/sh
# Self-report hook for claude and codex, installed into their hook
# configs by ~/.config/rex/agent-resume/install-hooks.sh. The agent
# runs it on
# SessionStart with a JSON payload on stdin; it records which
# conversation belongs to this Rex block, so a restored terminal resumes
# the exact session that ran in it. Invoked as:
#   bash ~/.config/rex/agent-resume/hooks/rex-agent-state.sh claude
#   bash ~/.config/rex/agent-resume/hooks/rex-agent-state.sh codex
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

# Claude exports nothing like CODEX_THREAD_ID, and nested claude runs
# are the common case: a `claude -p` fired by the Bash tool inherits
# REX_BLOCK, fires SessionStart, and would overwrite the pane's tsv line
# with the nested conversation's id — after a restart that pane would
# resume the wrong chat. So decide from the process tree: one ps
# snapshot, then an awk walk up this hook's parent chain asking which
# agent programs are really there.

# Classify one command line as one of our agents, "other" for someone
# else's, "" for not an agent. The basename of the first word covers
# normal installs; agents run through an interpreter (node-shimmed CLIs
# report as env or node) are recognized by their package in the rest of
# the command line. "other" agents are never recorded, but several of
# them run hooks in Claude Code's format (some share its settings), and
# their reports must not be taken for the agent this hook serves.
AGENT_AWK='
  function agent_of(args,   a0, base, rest) {
    a0 = args; sub(/[ \t].*/, "", a0)
    base = a0; sub(/.*\//, "", base); sub(/^[-.]+/, "", base)
    if (base ~ /^claude([-_.].*)?$/) return "claude"
    if (base ~ /^codex([-_.].*)?$/) return "codex"
    if (base ~ /^pi$/) return "pi"
    if (base ~ /^(node|bun|deno|[Pp]ython[0-9.]*)$/) {
      rest = args
      if (rest ~ /claude-code/) return "claude"
      if (rest ~ /@openai\/codex/) return "codex"
      if (rest ~ /pi-coding-agent/) return "pi"
    }
    if (base ~ /^(grok|gemini|copilot|cursor-agent|opencode|droid|agy|devin|kimi|qoder|qwen|letta|omp|kilo)([-_.].*)?$/) return "other"
    return ""
  }
'

# Print "AGENT COUNT" for the processes above this hook: AGENT is the
# nearest agent ("-" when none was recognized), COUNT the number of
# distinct agent runs — an agent adjacent to itself (a launcher shim
# starting a copy of itself) counts once, the same agent twice with a
# shell between counts twice. _REX_AGENT_RESTORE_STOP_PID is a seam for
# the tests only: the walk stops at that pid so a synthetic chain can be
# judged without the test runner's own ancestry. The 64-hop bound keeps
# a broken parent map from looping forever.
found=$(ps -axo pid=,ppid=,args= 2>/dev/null \
    | awk -v start="$$" -v stop="${_REX_AGENT_RESTORE_STOP_PID:-0}" "$AGENT_AWK"'
    {
        pid = $1; ppid = $2
        $1 = ""; $2 = ""
        sub(/^[ \t]+/, "")
        parent[pid] = ppid; cmd[pid] = $0
    }
    END {
        p = parent[start]; hops = 0; count = 0; first = ""; prev = ""
        while (p != "" && p > 1 && p != stop && hops < 64) {
            a = agent_of(cmd[p])
            if (a != "" && a != prev) {
                count++
                if (first == "") first = a
            }
            prev = a
            p = parent[p]; hops++
        }
        printf "%s %d\n", (first == "" ? "-" : first), count
    }' 2>/dev/null)
read -r nearest count <<EOF
${found:-- 0}
EOF
case "$count" in '' | *[!0-9]*) count=0 ;; esac

# More than one agent run in the chain means an agent was started from
# inside another agent (a headless `claude -p` from a tool shell): skip,
# and never let the nested one replace the pane's conversation.
[ "$count" -le 1 ] || exit 0
# A nearest agent that is not the one this hook was installed for means
# some other program ran this hook: skip rather than misattribute it.
[ "$nearest" = - ] || [ "$nearest" = "$agent" ] || exit 0
# No agent recognizable in the chain at all: record as before and trust
# the argument — ps may be unavailable or the chain unusual (a wrapper
# install, a container), and a ps quirk must never lose a real report.

cache="${XDG_CACHE_HOME:-$HOME/.cache}/rex-agent-resume"
mkdir -p "$cache" 2>/dev/null || exit 0
sessions="$cache/sessions.tsv"
lock="$cache/.sessions.lock"

# Short lock; on contention give up (another report for another block
# will land soon enough from its own hook run). A lock orphaned by a
# killed hook is taken over after a minute, or every future report on
# this machine would starve. 50 ms sleeps when sleep takes fractions,
# else whole seconds and few of them, so the agent is never held up on
# its hook timeout.
i=0
took=0
if sleep 0.01 >/dev/null 2>&1; then unit=0.05 tries=20; else unit=1 tries=3; fi
while ! mkdir "$lock" 2>/dev/null; do
    if [ "$took" -eq 0 ] \
        && [ -n "$(find "$lock" -type d -mmin +1 2>/dev/null)" ]; then
        took=1
        rmdir "$lock" 2>/dev/null
        continue
    fi
    i=$((i + 1))
    [ "$i" -lt "$tries" ] || exit 0
    sleep "$unit" 2>/dev/null
done
trap 'rmdir "$lock" 2>/dev/null' EXIT

tmp="$sessions.tmp"
{
    # Keep this block's replacement plus anything from the last 30 days;
    # the recorder's freshness window never reaches older refs anyway.
    cutoff=$(( $(date +%s) - 30 * 86400 ))
    awk -F'\t' -v b="$REX_BLOCK" -v cutoff="$cutoff" \
        '$1 != b && $4 + 0 > cutoff' "$sessions" 2>/dev/null
    printf '%s\t%s\t%s\t%s\n' "$REX_BLOCK" "$agent" "$session" "$(date +%s)"
} >"$tmp" && mv "$tmp" "$sessions"

exit 0
