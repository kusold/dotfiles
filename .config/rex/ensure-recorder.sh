#!/bin/sh
# Keep exactly one recorder running: rex do recorder.lua --all.
# Called from the zsh prescript and ~/.bashrc in every Rex terminal,
# which is itself the reliable fallback: restored terminals always spawn
# a shell on the server, so the recorder comes back with them.

[ -n "${REX_BLOCK:-}" ] || exit 0
[ "${REX_AGENT_RESUME:-1}" = "0" ] && exit 0

script="$HOME/.config/rex/recorder.lua"
[ -f "$script" ] || exit 0

rex_bin=$(command -v rex 2>/dev/null)
if [ -z "$rex_bin" ] && [ -n "${REX_BIN_DIR:-}" ] && [ -x "$REX_BIN_DIR/rex" ]; then
    rex_bin="$REX_BIN_DIR/rex"
fi
[ -n "$rex_bin" ] || exit 0

cache="${XDG_CACHE_HOME:-$HOME/.cache}/rex-agent-resume"
mkdir -p "$cache" 2>/dev/null || exit 0
pidfile="$cache/recorder.pid"

recorder_running() {
    pid=$(cat "$pidfile" 2>/dev/null)
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null \
        && ps -o command= -p "$pid" 2>/dev/null | grep -q "recorder[.]lua"
}

# The recorder writes the pidfile itself, whichever parent started it
# (init.lua at server start, or an earlier shell). Between its start and
# that write, fall back to a process scan.
if recorder_running; then
    exit 0
fi
if command -v pgrep >/dev/null 2>&1 \
    && pgrep -f "rex do.*recorder[.]lua" >/dev/null 2>&1; then
    exit 0
fi

# Serialize shells restored in the same instant: the first through the
# lock spawns the recorder, the rest find it through the pidfile.
lock="$cache/.recorder.lock"
if ! mkdir "$lock" 2>/dev/null; then
    i=0
    while ! recorder_running && [ "$i" -lt 20 ]; do
        i=$((i + 1))
        sleep 0.05 2>/dev/null || sleep 1
    done
    exit 0
fi
trap 'rmdir "$lock" 2>/dev/null' EXIT

if recorder_running; then
    exit 0
fi
# do is an argument of rex, not the keyword shellcheck takes it for
# shellcheck disable=SC1010
nohup "$rex_bin" do "$script" --all >/dev/null 2>&1 &
echo $! >"$pidfile"
