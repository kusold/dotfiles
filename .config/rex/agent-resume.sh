#!/bin/sh
# Print a command that resumes the coding-agent session (claude, codex,
# or pi) for a Rex terminal that Rex restored after a restart. Empty
# output means nothing to resume. Sourced from
# ~/.config/zsh/prescripts/rex-agent-resume.sh and ~/.bashrc, which run
# the printed command; the agent runs as a child of the shell, so
# exiting it drops back at the prompt.
#
# How it tells a restored terminal from a new one: Rex brings sessions
# back after a restart with the same block IDs (REX_BLOCK) but as fresh
# shells in the directory they were left in. The first shell Rex starts
# in a block lays down a marker; a later shell in the same block is a
# restored one. What to resume is then decided layer by layer:
#
#   1. recorder.tsv (written by ~/.config/rex/recorder.lua) says which
#      program had the foreground in this block. A plain foreground
#      (shell, vim) at the end means: do not resume anything.
#   2. sessions.tsv (written by the agents' self-report hooks) gives the
#      exact conversation id for this block; the first restored block to
#      take an id gets it, a second one degrades to a plain shell.
#   3. The recorder's agent name picks that agent's newest session file
#      for this directory.
#   4. Fallback when no recorder state exists: the newest session file
#      for this directory across all agents.
#
#   claude  ~/.claude/projects/<cwd, non-alphanumerics as ->/<uuid>.jsonl
#   codex   ~/.codex/sessions/YYYY/MM/DD/rollout-*-<uuid>.jsonl
#   pi      ~/.pi/agent/sessions/<encoded cwd>/<timestamp>_<uuid>.jsonl
#   (codex and pi carry "cwd" and "id" in the first record of the file)
#
# Set REX_AGENT_RESUME=0 to disable. Set REX_AGENT_RESUME_MAX_AGE_DAYS
# (default 7) to skip stale sessions; 0 disables resuming entirely.
# Set REX_AGENT_RESUME_FORCE=1 to ignore the nested-shell guard (testing).

set -u

[ -n "${REX_BLOCK:-}" ] || exit 0
[ "${REX_AGENT_RESUME:-1}" = "0" ] && exit 0

cache="${XDG_CACHE_HOME:-$HOME/.cache}/rex-agent-resume"
mkdir -p "$cache" 2>/dev/null || exit 0
id=$(printf '%s' "$REX_BLOCK" | tr '/:' '__')
marker="$cache/$id"

# Markers for blocks that no longer exist are cleaned up opportunistically.
find "$cache" -type f -mtime +30 -delete >/dev/null 2>&1 &

if [ ! -e "$marker" ]; then
    # First shell in this Rex block: remember it, nothing to resume.
    touch "$marker"
    exit 0
fi

# A shell started inside another shell (someone ran zsh/bash at a prompt)
# must not resume anything, even though the marker exists.
if [ -z "${REX_AGENT_RESUME_FORCE:-}" ] && command -v ps >/dev/null 2>&1; then
    parent=$(ps -o comm= -p "$PPID" 2>/dev/null)
    case "$parent" in
        *zsh* | *bash*) exit 0 ;;
    esac
fi

max_age="${REX_AGENT_RESUME_MAX_AGE_DAYS:-7}"
case "$max_age" in
    '' | *[!0-9]*) max_age=7 ;;
esac
[ "$max_age" -gt 0 ] || exit 0
now=$(date +%s)
fresh() { [ "$1" -ge $((now - max_age * 86400)) ]; }

# A field from this block's line in a TSV state file: get <file> <field>
get() { awk -F'\t' -v b="$REX_BLOCK" '$1 == b { print $'"$2"'; exit }' "$1" 2>/dev/null; }

recorder="$cache/recorder.tsv"
sessions="$cache/sessions.tsv"

c_agent=$(get "$recorder" 2)
c_ts=$(get "$recorder" 5)

# Layer 1: the recorder saw a plain foreground (shell, vim, ...) last in
# this block, recently: nothing was running, nothing to resume. (c_ts is
# the entry-existence signal; the agent field itself is empty here.)
if [ -n "$c_ts" ] && fresh "$c_ts" && [ -z "$c_agent" ]; then
    exit 0
fi

# True when the file was modified within the resume age window.
# (find -mtime +N prints only files older than N days.)
recent_file() {
    [ -z "$(find "$1" -mtime +"$max_age" -print -quit 2>/dev/null)" ]
}

cwd_pattern=$(printf '%s' "$PWD" | sed 's/[.[\*^$]/\\&/g')
id_in() { head -c 2000 "$1" 2>/dev/null | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4; }
mtime_of() {
    stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || printf '0'
}

find_claude() {
    project=$(printf '%s' "$PWD" | sed 's/[^A-Za-z0-9]/-/g')
    for f in $(ls -t "$HOME/.claude/projects/$project/"*.jsonl 2>/dev/null | head -5); do
        if recent_file "$f" && head -c 2000 "$f" 2>/dev/null \
            | grep -q "\"cwd\":\"$cwd_pattern\""; then
            printf '%s\n' "$f"
            return
        fi
    done
}

scan_agent_dir() {
    find "$1" -name '*.jsonl' -mtime -$(($max_age + 1)) -print0 2>/dev/null \
        | xargs -0 ls -t 2>/dev/null | head -40 | while IFS= read -r f; do
            [ -n "$f" ] || continue
            if recent_file "$f" && head -c 2000 "$f" 2>/dev/null \
                | grep -q "\"cwd\":\"$cwd_pattern\""; then
                printf '%s\n' "$f"
                return
            fi
        done
}

find_codex() { scan_agent_dir "$HOME/.codex/sessions"; }
find_pi() { scan_agent_dir "$HOME/.pi/agent/sessions"; }

session_id_of() {
    case "$1" in
    */.claude/*) basename "$1" .jsonl ;;
    *) id_in "$1" ;;
    esac
}

emit() { # emit <agent> <session-id>
    case "$1" in
    claude) printf 'claude --resume %s\n' "$2" ;;
    codex) printf 'codex resume %s\n' "$2" ;;
    pi) printf 'pi --session %s\n' "$2" ;;
    esac
}

# Layer 2: an agent's own hook recorded the exact conversation id for
# this block. First restored block to take it wins; a duplicate degrades
# to a shell instead of forking the same conversation twice.
b_agent=$(get "$sessions" 2)
b_session=$(get "$sessions" 3)
b_ts=$(get "$sessions" 4)
if [ -n "$b_agent" ] && [ -n "$b_session" ] && [ -n "$b_ts" ] && fresh "$b_ts"; then
    # The ref is a uuid for claude/codex but a file path for pi; cksum
    # makes it safe as a filename either way.
    consumed="$cache/consumed/$b_agent-$(printf '%s' "$b_session" | cksum | cut -d' ' -f1)"
    mkdir -p "$cache/consumed" 2>/dev/null
    if [ ! -e "$consumed" ] || [ "$(mtime_of "$consumed")" -lt "$b_ts" ]; then
        touch "$consumed"
        emit "$b_agent" "$b_session"
    fi
    # This block's conversation is taken by a sibling pane (or was just
    # resumed by this one): degrade to a shell instead of resuming a
    # different session that never ran here.
    exit 0
fi

# Layer 3: the recorder knows which agent had the foreground in this
# block; take that agent's newest session for this directory.
if [ -n "$c_agent" ] && [ -n "$c_ts" ] && fresh "$c_ts"; then
    f=$(eval "find_$c_agent" 2>/dev/null)
    if [ -n "$f" ]; then
        emit "$c_agent" "$(session_id_of "$f")"
        exit 0
    fi
fi

# Layer 4: no recorder state; newest session for this directory across
# all agents.
best=
best_mtime=0
for agent in claude codex pi; do
    f=$(eval "find_$agent" 2>/dev/null)
    [ -n "$f" ] || continue
    m=$(mtime_of "$f")
    if [ "$m" -gt "$best_mtime" ]; then
        best=$agent
        best_file=$f
        best_mtime=$m
    fi
done
[ -n "$best" ] || exit 0
emit "$best" "$(session_id_of "$best_file")"
