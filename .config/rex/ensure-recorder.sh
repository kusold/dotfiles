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

pid=$(cat "$pidfile" 2>/dev/null)
if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null \
    && ps -o command= -p "$pid" 2>/dev/null | grep -q "recorder[.]lua"; then
    exit 0
fi

nohup "$rex_bin" do "$script" --all >/dev/null 2>&1 &
echo $! >"$pidfile"
