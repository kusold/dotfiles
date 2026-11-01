#!/usr/bin/env bash
# End-to-end tests for agent-resume, run against a real, throwaway Rex
# server: fake coding agents hold panes, the server restarts underneath
# them, and the harness checks that the right conversations come back.
# The live Rex server, the real agent configs (~/.claude, ~/.codex,
# ~/.pi) and the real cache (~/.cache/rex-agent-resume) are never
# touched; the last is asserted explicitly at the end.
#
# What it covers, one server generation per env shape:
#   A (default env, debug log on)
#     - install-hooks --ensure wired the sandbox agent configs
#     - a running agent is recorded (recorder.json entry + sessions.tsv
#       ref, reported by the real hook fired by the fake agent)
#     - the nested-agent guard: a claude started from inside the pane's
#       claude reports and is skipped; the pane's ref line is
#       byte-identical before and after
#     - codex drops a report belonging to a foreign thread id
#     - a busy pane is never typed into: agent_resume_now queues, the
#       recorder logs a busy skip, nothing is delivered
#     - quitting an agent drops its recording (the event path)
#     - after a restart: claude and codex resume their exact ids in
#       their saved directories (one path with a space in it), pi
#       resumes the session path recorded in sessions.tsv, and the pane
#       whose agent was quit before the restart stays at its shell
#     - the consumed check: of two restored panes with no recorded ref
#       only one gets the claude --continue fallback, and
#       agent_resume_now re-delivers into the other by hand
#     - agent_resume_forget clears both the recording and the tsv ref
#   B (REX_AGENT_RESUME_MODE=prompt)
#     - the resume command is typed and waits: nothing runs until Enter
#     - Enter settles the pending hold at once (the agent's start in the
#       fresh epoch adopts the generation the sweep could not)
#     - a delivery left waiting survives a sweep (the pending hold), and
#       agent_resume_now re-delivers it after the line is cleared
#   C (REX_AGENT_RESUME=0)
#     - nothing resumes, the recordings are left untouched, and the
#       manual actions stay unregistered
#
# Sandbox design: everything lives under one mktemp dir — its own server
# socket and state, a HOME whose ~/.config/rex symlinks to this repo (so
# the server runs the real init.lua, recorder and hooks), a redirected
# XDG_CACHE_HOME, and empty agent config dirs for install-hooks to fill.
# The server is double-forked and setsid-detached on purpose: this
# harness often runs inside a coding agent, and the hooks' nested-agent
# guard walks parent chains — a server parented on the harness would
# make every report look nested and silently skip. One session per pane
# rather than splits, so every pane is a full-width window: the typed
# resume commands these tests grep for would wrap in narrow split panes.
#
# The fake agents are python3 scripts installed where their own paths
# carry the package marker ($D/fake/claude-code/bin/claude,
# $D/fake/@openai/codex/codex, $D/fake/pi-coding-agent/bin/pi): this Rex
# only reports a foreground `script` field for python/node programs, and
# the hook's ps walk classifies interpreter lines by those package
# substrings — a bash script in those places would be invisible to both.
# The fakes fire the real rex-agent-state.sh hook exactly as the real
# agents do. The pi extension is TypeScript for the real pi runtime and
# cannot run here, so its report is simulated by appending the
# sessions.tsv line directly (same format, a ref with a space in it);
# the extension itself is only covered by real-pi use.
#
# Requires rex, zsh, jq and python3 on PATH; skips with exit 0 when any
# is missing, so CI stays green on machines without Rex. Expected
# runtime: about 2 minutes, dominated by two deliberate waits — a 35s
# sweep-cycle pause in generation B, and ~3s settles before every server
# stop so no self-report hook is orphaned mid-write holding sessions.tsv's
# lock (later hooks would then give up on it for a minute by design).
#
# Run it as:  .config/rex/agent-resume/test/e2e.sh
# Keep the sandbox for inspection with E2E_KEEP=1.
set -u

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
for cmd in rex zsh jq python3; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "e2e: $cmd not found; skipping"
        exit 0
    }
done

# The harness must never fall back to the live server by accident: every
# rex call goes through R with an explicit -S, and the inherited
# location vars are dropped so no block-scoped default kicks in.
unset REX_SERVER REX_SESSION REX_BLOCK REX_CLIENT

D="$(mktemp -d /tmp/e2e-ar.XXXXXX)"   # shallow: unix sockets cap at ~104 chars
SOCK="unix://$D/s"
LOG="$D/agents.log"
SEQ="$D/seq"
CACHE="$D/cache/rex-agent-resume"
HOOK="$D/home/.config/rex/agent-resume/hooks/rex-agent-state.sh"
HOOK_TS="$D/home/.config/rex/agent-resume/hooks/rex-agent-state.ts"
PROJDIR="$D/proj dir"                 # the space is the point: quoting end to end
PROJ2="$D/proj2"
PROJ4="$D/proj4"
SERVER_PID=""

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }
check() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi }

R() { rex -S "$SOCK" --autostart=false "$@"; }

# wait_for SECONDS COMMAND...: poll until COMMAND succeeds.
wait_for() {
    local secs="$1" i
    shift
    for i in $(seq 1 $((secs * 10))); do
        "$@" >/dev/null 2>&1 && return 0
        sleep 0.1
    done
    return 1
}

start_server() { # start_server [VAR=VAL ...]: extra env for this generation
    # Double fork + setsid, so the server is not our descendant (see the
    # header). Everything the system reads comes from this environment:
    # the throwaway HOME and cache, the sandbox agent configs, and the
    # REX_AGENT_RESUME_* knobs under test.
    local extra=("$@")
    ( setsid env -u REX_SERVER -u REX_SESSION -u REX_BLOCK -u REX_CLIENT \
        -u _REX_AGENT_RESTORE_STOP_PID -u REX_AGENT_RESUME \
        -u REX_AGENT_RESUME_MODE -u REX_AGENT_RESUME_MAX_AGE_DAYS \
        REX_SERVER="$SOCK" REX_AGENT_RESUME_DEBUG=1 \
        HOME="$D/home" XDG_CONFIG_HOME="$D/home/.config" \
        XDG_CACHE_HOME="$D/cache" ZDOTDIR="$D/zdot" \
        CLAUDE_CONFIG_DIR="$D/agents/claude" CODEX_HOME="$D/agents/codex" \
        PI_CODING_AGENT_DIR="$D/agents/pi/agent" \
        AGENTS_LOG="$LOG" AGENTS_SEQ="$SEQ" HOOK_SH="$HOOK" \
        PATH="$F_CLAUDE:$F_CODEX:$F_PI:$PATH" \
        ${extra[@]+"${extra[@]}"} \
        rex server run --listen "$SOCK" --state-dir "$D/rexstate" \
        --config "$D/home/.config/rex/init.lua" \
        >> "$D/server.log" 2>&1 < /dev/null & )
    local i
    for i in $(seq 1 150); do
        if R ls >/dev/null 2>&1; then
            SERVER_PID="$(R whoami --json 2>/dev/null | jq -r '.pid // empty')"
            return 0
        fi
        sleep 0.1
    done
    echo "test server did not start; last log lines:"
    tail -30 "$D/server.log"
    exit 1
}

stop_server() {
    # Let any in-flight self-report hook finish first: a hook killed
    # mid-write orphans .sessions.lock, and every later hook then gives
    # up on it for a full minute by design — enough to flake the rest.
    sleep 3
    R server stop >/dev/null 2>&1
    local i
    for i in $(seq 1 150); do
        kill -0 "$SERVER_PID" 2>/dev/null || return 0
        sleep 0.1
    done
    kill "$SERVER_PID" 2>/dev/null
    sleep 1
}

cleanup() {
    [ -n "$SERVER_PID" ] && R server stop >/dev/null 2>&1
    pkill -f "$D/fake/" 2>/dev/null          # any fake agent left holding a pty
    pkill -f "$D/rexstate" 2>/dev/null       # a server that ignored the stop
    [ -z "${E2E_KEEP:-}" ] && rm -rf "$D"
    return 0
}
trap cleanup EXIT

# --- fixtures -------------------------------------------------------------

mkdir -p "$D/home/.config" "$D/cache" "$D/zdot" "$D/agents/claude" \
    "$D/agents/codex" "$D/agents/pi/agent" "$PROJDIR" "$PROJ2" "$PROJ4"
: > "$LOG"
echo 0 > "$SEQ"

# The server runs this repo's real config; only its environment is fake.
ln -s "$ROOT/.config/rex" "$D/home/.config/rex"

# The fake agent: one python3 program per agent, sed'd into the marker
# paths (see header for why python3 and why those paths).
cat > "$D/fake-agent.py" <<'EOF'
#!/usr/bin/env python3
import os, subprocess, sys, time

AGENT = "__AGENT__"
args = sys.argv[1:]
probe = os.environ.get("AR_PROBE") == "1"

def next_seq():
    with open(os.environ["AGENTS_SEQ"]) as f:
        n = int(f.read().strip() or 0)
    with open(os.environ["AGENTS_SEQ"], "w") as f:
        f.write(str(n + 1))
    return n + 1

# The conversation id: the one we were told to resume, else a fresh one,
# so every resume cycle gets its own command and nothing is masked by
# the recorder's consumed check.
if AGENT == "claude" and "--resume" in args:
    cid = args[args.index("--resume") + 1]
elif AGENT == "codex" and args[:1] == ["resume"]:
    cid = args[1]
elif AGENT == "pi" and "--session" in args:
    cid = args[args.index("--session") + 1]
else:
    cid = "e2e-%s-%d" % (AGENT, next_seq())

def log(line):
    with open(os.environ["AGENTS_LOG"], "a") as f:
        f.write(line + "\n")

log("%s %s args=[%s] id=%s" % (AGENT, "probe" if probe else "run",
                               " ".join(args), cid))

def report(session_id):
    payload = ('{"session_id":"%s","hook_event_name":"SessionStart",'
               '"cwd":"%s","source":"startup"}' % (session_id, os.getcwd()))
    env = dict(os.environ)
    if AGENT == "codex":
        env["CODEX_THREAD_ID"] = cid  # the owning thread, as real codex exports it
    subprocess.run(["bash", os.environ["HOOK_SH"], AGENT],
                   input=payload.encode(), env=env)

if os.environ.get("REX_BLOCK"):
    report(cid)
    if AGENT == "codex" and not args:
        # A report that belongs to another thread (a codex subagent):
        # the hook must drop it, or it replaces this pane's ref.
        report("e2e-codex-foreign-thread")
        log("codex thread-probe id=e2e-codex-foreign-thread")

if probe:
    sys.exit(0)  # the nested probe reports and leaves

if AGENT == "claude" and not args:
    # The nested-agent guard, exercised for real: a tool shell (bash -c)
    # inside this agent starts another claude that reports too. Delayed
    # a beat so the harness can snapshot sessions.tsv between the two
    # reports. The trailing "; true" matters: bash exec-optimizes a
    # lone simple command, which would leave the two claudes adjacent
    # in the process tree — the shape the guard deliberately counts as
    # one run (a launcher shim) rather than two.
    time.sleep(1.0)
    env = dict(os.environ)
    env["AR_PROBE"] = "1"
    subprocess.run(
        ["bash", "-c", '"%s" --probe; true' % os.path.abspath(__file__)],
        env=env)

# Hold the pane like a real agent until quit.
try:
    time.sleep(3600)
except KeyboardInterrupt:
    pass
EOF

F_CLAUDE="$D/fake/claude-code/bin"
F_CODEX="$D/fake/@openai/codex"
F_PI="$D/fake/pi-coding-agent/bin"
install_fake() { # install_fake <agent> <bindir>
    mkdir -p "$2"
    sed "s/__AGENT__/$1/g" "$D/fake-agent.py" > "$2/$1"
    chmod +x "$2/$1"
}
install_fake claude "$F_CLAUDE"
install_fake codex "$F_CODEX"
install_fake pi "$F_PI"

# Present, or zsh runs its new-user install menu into the pane. The
# fakes lead PATH here as well as in the server env: a login shell's
# profile can rewrite PATH, and a typed claude must resolve to the fake.
cat > "$D/zdot/.zshrc" <<EOF
PS1='e2e%% '
path=("$F_CLAUDE" "$F_CODEX" "$F_PI" \$path)
EOF

# --- helpers --------------------------------------------------------------

cap() { R capture -s "$1" -b "$2" --trim --unwrap 2>/dev/null; }
screen_has() { cap "$1" "$2" | grep -qF -- "$3"; }
log_has() { grep -qF -- "$1" "$LOG" 2>/dev/null; }
# Only agent runs, not the nested probes: a probe logs about a second
# after its pane's agent starts, so a whole-file count snapshotted the
# moment the recording lands can still grow when the probe line arrives.
run_lines() { grep -cE '^(claude|codex|pi) run ' "$LOG" 2>/dev/null || true; }
ref_of() { awk -F'\t' -v b="$1" '$1 == b {print $3}' "$CACHE/sessions.tsv" 2>/dev/null | tail -1; }
ref_line() { awk -F'\t' -v b="$1" '$1 == b' "$CACHE/sessions.tsv" 2>/dev/null; }
ref_gone() { [ -z "$(ref_of "$1")" ]; }
recorded_as() { jq -e --arg b "$1" --arg a "$2" '.[$b].agent == $a' "$CACHE/recorder.json" >/dev/null 2>&1; }
has_entry() { jq -e --arg b "$1" 'has($b)' "$CACHE/recorder.json" >/dev/null 2>&1; }
entry_gone() { jq -e --arg b "$1" 'has($b) | not' "$CACHE/recorder.json" >/dev/null 2>&1; }
pending_flag() { jq -e --arg b "$1" '.[$b].pending == true' "$CACHE/recorder.json" >/dev/null 2>&1; }
pending_cleared() { jq -e --arg b "$1" '.[$b] != null and .[$b].pending != true' "$CACHE/recorder.json" >/dev/null 2>&1; }
fg_pid() { R block call -s "$1" -b "$2" process 2>/dev/null | jq -r '.foreground.pid // empty'; }
fg_name() { R block call -s "$1" -b "$2" process 2>/dev/null | jq -r '.foreground.name // empty'; }
fg_cwd() { R block call -s "$1" -b "$2" process 2>/dev/null | jq -r '.foreground.cwd // empty'; }
at_prompt() { [ "$(fg_name "$1" "$2")" = zsh ]; }
kill_agent() { local p; p="$(fg_pid "$1" "$2")"; [ -n "$p" ] && kill "$p" 2>/dev/null; }
cont_runs() { [ "$(grep -cF -- 'claude run args=[--continue]' "$LOG" 2>/dev/null || true)" -ge "$1" ]; }
pane_new() { # pane_new LABEL DIR -> sets PANE_SID / PANE_BID
    local out
    out="$(R new "$1" -c "$2" --json)" || return 1
    PANE_SID="$(printf '%s' "$out" | jq -r .session_id)"
    PANE_BID="$(printf '%s' "$out" | jq -r '.initial_windows[0].block_ids[0]')"
}

# Isolation guard: snapshot whether this machine already has a real
# ~/.cache/rex-agent-resume before anything runs, so the final check
# catches the sandbox creating one without failing on a machine that
# simply uses agent-resume for real.
REAL_CACHE="$HOME/.cache/rex-agent-resume"
REAL_CACHE_BEFORE="absent"
[ -e "$REAL_CACHE" ] && REAL_CACHE_BEFORE="present"

echo "agent-resume e2e (sandbox at $D)"

# === generation A: default env, debug log on ==============================

start_server
check "install-hooks filled the sandbox claude config" \
    'wait_for 15 grep -q rex-agent-state "$D/agents/claude/settings.json"' \
    "$(ls -la "$D/agents/claude" 2>/dev/null)"
check "install-hooks enabled codex hooks" \
    'wait_for 15 grep -q "^\[features\]" "$D/agents/codex/config.toml" && grep -q "^hooks *= *true" "$D/agents/codex/config.toml"' \
    "$(cat "$D/agents/codex/config.toml" 2>/dev/null)"
check "install-hooks installed the codex hook entry" \
    'grep -q rex-agent-state "$D/agents/codex/hooks.json"' \
    "$(cat "$D/agents/codex/hooks.json" 2>/dev/null)"
check "install-hooks copied the pi extension" \
    'cmp -s "$HOOK_TS" "$D/agents/pi/agent/extensions/rex-agent-state.ts"' \
    "$(ls "$D/agents/pi/agent/extensions" 2>/dev/null)"

# One session per pane (full-width windows; see header). BA runs claude
# in the spaced folder, BQ is the one that will be quit, BC codex, BP
# pi, BD/BE the ref-less pair for the fallback/consumed checks.
pane_new e2e-claude "$PROJDIR"; SA="$PANE_SID"; BA="$PANE_BID"
check "claude pane is ready" 'wait_for 15 screen_has "$SA" "$BA" "e2e%"' "$(cap "$SA" "$BA" | tail -3)"
R send -s "$SA" -b "$BA" 'echo "P:$ZDOTDIR"'$'\r'
check "the pane runs inside the sandbox env" 'wait_for 5 screen_has "$SA" "$BA" "P:$D/zdot"' "$(cap "$SA" "$BA" | tail -3)"

R send -s "$SA" -b "$BA" 'claude'$'\r'
check "the recorder saves the block with its agent" 'wait_for 20 recorded_as "$BA" claude' "$(cat "$CACHE/recorder.json" 2>/dev/null)"
check "the self-report hook recorded a ref" 'wait_for 20 [ -n "$(ref_of "$BA")" ]' "$(cat "$CACHE/sessions.tsv" 2>/dev/null)"
R1="$(ref_of "$BA")"
check "the fake agent ran with that very id" 'log_has "claude run args=[] id=$R1"' "$(grep '^claude' "$LOG" 2>/dev/null)"

# The nested-agent guard: snapshot the pane's tsv line, let the probe
# fire (a claude under a bash -c inside the pane's claude), compare.
before="$(ref_line "$BA")"
check "the nested probe actually ran" 'wait_for 15 log_has "claude probe args=[--probe]"' "$(cat "$LOG")"
sleep 1.5  # the probe's hook has either landed or been skipped by now
PROBE_ID="$(sed -n 's/^claude probe args=\[--probe\] id=//p' "$LOG" | tail -1)"
check "the nested claude's report leaves the ref byte-identical" \
    '[ -n "$before" ] && [ "$before" = "$(ref_line "$BA")" ] && [ "$(ref_line "$BA" | wc -l)" -eq 1 ]' \
    "before=[$before] after=[$(ref_line "$BA")]"
check "the nested conversation never reached sessions.tsv" \
    '[ -n "$PROBE_ID" ] && ! grep -qF "$PROBE_ID" "$CACHE/sessions.tsv"' \
    "probe id=[$PROBE_ID] tsv=$(cat "$CACHE/sessions.tsv" 2>/dev/null)"

pane_new e2e-quit "$PROJ2"; SQ="$PANE_SID"; BQ="$PANE_BID"
check "quit pane is ready" 'wait_for 15 screen_has "$SQ" "$BQ" "e2e%"' "$(cap "$SQ" "$BQ" | tail -3)"
R send -s "$SQ" -b "$BQ" 'claude'$'\r'
check "the quit pane's agent is recorded too" 'wait_for 20 recorded_as "$BQ" claude' "$(cat "$CACHE/recorder.json" 2>/dev/null)"
RQ="$(ref_of "$BQ")"

# Busy check, on the pane that is about to be quit anyway: a manual
# resume marks its command consumed even when skipped as busy (by
# design — the recovery lever is the action itself), so target a block
# whose auto-resume nobody depends on.
RUNS_BEFORE="$(grep -c '^claude run' "$LOG" 2>/dev/null || true)"
out="$(R do agent_resume_now block_id="$BQ" session_id="$SQ" 2>&1)"
check "agent_resume_now queues while the agent holds the pane" \
    'printf "%s" "$out" | grep -q "resume queued for $BQ"' "$out"
check "the recorder refuses to type into a busy pane" \
    'wait_for 10 grep -qF "busy skip: $BQ" "$CACHE/debug.log"' \
    "$(tail -5 "$CACHE/debug.log" 2>/dev/null)"
check "nothing was delivered to the busy pane" \
    '[ "$(grep -c "^claude run" "$LOG" 2>/dev/null || true)" -eq "$RUNS_BEFORE" ]' "$(cat "$LOG")"

kill_agent "$SQ" "$BQ"
check "quitting the agent drops the recording (event path)" 'wait_for 10 entry_gone "$BQ"' "$(cat "$CACHE/recorder.json" 2>/dev/null)"
check "the quit pane is back at its prompt" 'wait_for 10 at_prompt "$SQ" "$BQ"' "$(cap "$SQ" "$BQ" | tail -3)"

pane_new e2e-codex "$PROJDIR"; SC="$PANE_SID"; BC="$PANE_BID"
check "codex pane is ready" 'wait_for 15 screen_has "$SC" "$BC" "e2e%"' "$(cap "$SC" "$BC" | tail -3)"
R send -s "$SC" -b "$BC" 'codex'$'\r'
check "the recorder saves the codex block" 'wait_for 20 recorded_as "$BC" codex' "$(cat "$CACHE/recorder.json" 2>/dev/null)"
check "codex recorded a ref" 'wait_for 20 [ -n "$(ref_of "$BC")" ]' "$(cat "$CACHE/sessions.tsv" 2>/dev/null)"
R2="$(ref_of "$BC")"
check "the fake codex ran with that very id" 'log_has "codex run args=[] id=$R2"' "$(grep '^codex' "$LOG" 2>/dev/null)"
check "the foreign-thread report ran" 'log_has "codex thread-probe"' "$(grep '^codex' "$LOG" 2>/dev/null)"
sleep 1
check "the foreign-thread report never reached sessions.tsv" \
    '! grep -qF "e2e-codex-foreign-thread" "$CACHE/sessions.tsv"' \
    "$(cat "$CACHE/sessions.tsv" 2>/dev/null)"

# Two claude panes with no self-report (REX_BLOCK stripped from their
# env): recorded by the recorder alone, so at restore time both fall
# back to `claude --continue` — and the consumed check must let only
# one of them run it.
pane_new e2e-cont1 "$PROJ4"; SD="$PANE_SID"; BD="$PANE_BID"
pane_new e2e-cont2 "$PROJ4"; SE="$PANE_SID"; BE="$PANE_BID"
check "first ref-less pane is ready" 'wait_for 15 screen_has "$SD" "$BD" "e2e%"' "$(cap "$SD" "$BD" | tail -3)"
check "second ref-less pane is ready" 'wait_for 15 screen_has "$SE" "$BE" "e2e%"' "$(cap "$SE" "$BE" | tail -3)"
R send -s "$SD" -b "$BD" 'env -u REX_BLOCK claude'$'\r'
R send -s "$SE" -b "$BE" 'env -u REX_BLOCK claude'$'\r'
check "both ref-less panes are recorded" 'wait_for 20 recorded_as "$BD" claude && recorded_as "$BE" claude' "$(cat "$CACHE/recorder.json" 2>/dev/null)"
check "and neither wrote a ref" 'ref_gone "$BD" && ref_gone "$BE"' "$(cat "$CACHE/sessions.tsv" 2>/dev/null)"

# pi's report is simulated (the extension needs the real pi runtime):
# the same tsv line its extension would write, with the block id known
# first. The ref is a path with a space in it — pi resumes session
# files, and the quoting is part of what this proves. Nothing else can
# be mid-write in sessions.tsv here: the hooks fire only at agent start,
# and every agent has long since started.
pane_new e2e-pi "$PROJ2"; SP="$PANE_SID"; BP="$PANE_BID"
check "pi pane is ready" 'wait_for 15 screen_has "$SP" "$BP" "e2e%"' "$(cap "$SP" "$BP" | tail -3)"
PI_REF="$D/pi sessions/session one.json"
mkdir -p "$CACHE"
printf '%s\t%s\t%s\t%s\n' "$BP" pi "$PI_REF" "$(date +%s)" >> "$CACHE/sessions.tsv"
R send -s "$SP" -b "$BP" 'pi'$'\r'
check "the fake pi is recorded (path matching, no hook of its own)" 'wait_for 20 recorded_as "$BP" pi' "$(cat "$CACHE/recorder.json" 2>/dev/null)"
check "the fake pi ran" 'log_has "pi run args=[] id="' "$(grep '^pi' "$LOG" 2>/dev/null)"

stop_server
check "the recordings survive the stop" 'has_entry "$BA" && has_entry "$BC" && has_entry "$BP"' "$(cat "$CACHE/recorder.json" 2>/dev/null)"
start_server

echo "== generation A: restart, default env"

# The ref-less pair first: the skipped pane keeps its recording only
# until a sweep reads it as a quit (it is not pending — that hold is
# prompt-mode only), so exercise the manual lever inside that window.
check "one ref-less pane got the --continue fallback" 'wait_for 25 cont_runs 1' "$(cat "$LOG")"
if at_prompt "$SD" "$BD"; then IDLE_S="$SD"; IDLE_B="$BD"; else IDLE_S="$SE"; IDLE_B="$BE"; fi
check "the skipped pane kept its recording for a manual resume" 'has_entry "$IDLE_B"' "$(cat "$CACHE/recorder.json" 2>/dev/null)"
out="$(R do agent_resume_now block_id="$IDLE_B" session_id="$IDLE_S" 2>&1)"
check "agent_resume_now re-delivers by hand" \
    'printf "%s" "$out" | grep -q "resume queued for $IDLE_B" && wait_for 15 cont_runs 2' \
    "$out $(cap "$IDLE_S" "$IDLE_B" | tail -2)"

check "claude resumes its exact conversation" 'wait_for 25 log_has "claude run args=[--resume $R1] id=$R1"' "$(cat "$LOG")"
check "resumed claude runs in the saved (spaced) folder" '[ "$(fg_cwd "$SA" "$BA")" = "$PROJDIR" ]' "cwd=[$(fg_cwd "$SA" "$BA")] want=[$PROJDIR]"
check "codex resumes its exact conversation" 'wait_for 25 log_has "codex run args=[resume $R2] id=$R2"' "$(cat "$LOG")"
check "resumed codex runs in the saved folder" '[ "$(fg_cwd "$SC" "$BC")" = "$PROJDIR" ]' "cwd=[$(fg_cwd "$SC" "$BC")] want=[$PROJDIR]"
check "pi resumes the session path from sessions.tsv" 'wait_for 25 log_has "pi run args=[--session $PI_REF]"' "$(cat "$LOG")"
check "the quit pane stays at its shell after the restart" 'wait_for 15 at_prompt "$SQ" "$BQ"' "$(cap "$SQ" "$BQ" | tail -3)"
check "its conversation was never resumed" '! log_has "claude run args=[--resume $RQ]"' "$(cat "$LOG")"
check "and its recording is still gone" 'entry_gone "$BQ"' "$(cat "$CACHE/recorder.json" 2>/dev/null)"

out="$(R do agent_resume_forget block_id="$BC" 2>&1)"
check "agent_resume_forget queues" 'printf "%s" "$out" | grep -q "forget queued for $BC"' "$out"
check "forget clears the recording" 'wait_for 10 entry_gone "$BC"' "$(cat "$CACHE/recorder.json" 2>/dev/null)"
check "forget clears the sessions.tsv ref" 'wait_for 10 ref_gone "$BC"' "$(cat "$CACHE/sessions.tsv" 2>/dev/null)"
# The sweep re-records a running agent it has no entry for, so take
# this pane back to its shell before one comes around.
kill_agent "$SC" "$BC"
wait_for 10 at_prompt "$SC" "$BC"

# Fresh recordings for generation B, in panes whose previous commands
# are all long consumed: new ids mean resume commands nothing has taken.
R send -s "$SC" -b "$BC" 'claude'$'\r'
check "a fresh claude is recorded in the codex pane" 'wait_for 20 recorded_as "$BC" claude' "$(cat "$CACHE/recorder.json" 2>/dev/null)"
RB1="$(ref_of "$BC")"
R send -s "$SQ" -b "$BQ" 'claude'$'\r'
check "a fresh claude is recorded in the quit pane" 'wait_for 20 recorded_as "$BQ" claude' "$(cat "$CACHE/recorder.json" 2>/dev/null)"
RB2="$(ref_of "$BQ")"

# === generation B: prompt mode ============================================

stop_server
start_server REX_AGENT_RESUME_MODE=prompt
echo "== generation B: REX_AGENT_RESUME_MODE=prompt"

if wait_for 40 screen_has "$SC" "$BC" "claude --resume '$RB1'"; then
    ok "prompt mode types the resume command and withholds Enter"
else
    bad "prompt mode types the resume command and withholds Enter" "$(cap "$SC" "$BC" | tail -3)"
fi
check "nothing ran without the keystroke" '! log_has "claude run args=[--resume $RB1]"' "$(cat "$LOG")"
check "the recording is held pending" 'wait_for 10 pending_flag "$BC"' "$(cat "$CACHE/recorder.json" 2>/dev/null)"
check "the debug log names the prompt delivery" 'grep -qF "prompt delivery to $BC" "$CACHE/debug.log"' "$(grep prompt "$CACHE/debug.log" 2>/dev/null | tail -2)"
R send -s "$SC" -b "$BC" $'\r'
check "Enter runs the typed resume" 'wait_for 15 log_has "claude run args=[--resume $RB1] id=$RB1"' "$(cat "$LOG") $(cap "$SC" "$BC" | tail -2)"
# Enter settles the hold at once: the agent's start is the fresh epoch's
# first event, and the recording stops being pending. (A sweep-detected
# restore once left the generation on record stale-high, so this start
# was misread as another reset, bailed at the consumed check, and the
# flag stuck — leaving quit detection suppressed after a run the user
# had watched happen.)
check "Enter settles the pending hold" 'wait_for 10 pending_cleared "$BC"' "$(cat "$CACHE/recorder.json" 2>/dev/null)"
# Which dlog names the settlement depends on a startup race this test
# cannot control: when the sweep detects the restore (the recorder
# subscribed after the restore events fired), the generation on record
# is stale-high and the agent's start is logged as an adoption; when the
# event path detects it ("generation reset"), the fresh generation was
# adopted when the resume was scheduled and the start goes through the
# ordinary recording path. Both settle the hold; the flag sticking would
# fail the check above in either case.
check "the debug log names the settlement" \
    'grep -q "agent running again in $BC" "$CACHE/debug.log" || grep -q "restore detected: generation reset in $BC" "$CACHE/debug.log"' \
    "$(grep -E "agent running again|generation reset" "$CACHE/debug.log" 2>/dev/null | tail -3)"

if wait_for 40 screen_has "$SQ" "$BQ" "claude --resume '$RB2'"; then
    ok "the second pane's delivery also waits"
else
    bad "the second pane's delivery also waits" "$(cap "$SQ" "$BQ" | tail -3)"
fi
check "it did not run either" '! log_has "claude run args=[--resume $RB2]"' "$(cat "$LOG")"

# The one long wait: a full sweep cycle passes with the command still
# sitting unrun. The pane looks exactly like a quit; the pending hold is
# what keeps the recording alive for the lever below.
sleep 35
check "the sweep leaves a pending delivery alone" 'has_entry "$BQ" && pending_flag "$BQ"' "$(cat "$CACHE/recorder.json" 2>/dev/null)"
check "and it still has not run" '! log_has "claude run args=[--resume $RB2]"' "$(cat "$LOG")"

R send -s "$SQ" -b "$BQ" $'\025'  # Ctrl-U: clearing the line is the skip
out="$(R do agent_resume_now block_id="$BQ" session_id="$SQ" 2>&1)"
if wait_for 20 screen_has "$SQ" "$BQ" "claude --resume '$RB2'"; then
    line="$(cap "$SQ" "$BQ" | tail -1)"
    if printf '%s' "$out" | grep -q "resume queued for $BQ" \
        && [ "$(printf '%s\n' "$line" | grep -oF "claude --resume" | wc -l)" -eq 1 ]; then
        ok "agent_resume_now re-delivers after the sweep"
    else
        bad "agent_resume_now re-delivers after the sweep" "$out pane=[$line] (command typed more than once)"
    fi
else
    bad "agent_resume_now re-delivers after the sweep" "$out pane=[$(cap "$SQ" "$BQ" | tail -1)]"
fi
R send -s "$SQ" -b "$BQ" $'\r'
check "the re-delivered command runs" 'wait_for 15 log_has "claude run args=[--resume $RB2] id=$RB2"' "$(cat "$LOG")"

# === generation C: disabled =================================================

# Two more fresh recordings, so the disabled generation is tested
# against commands nothing has consumed yet — otherwise it would pass
# vacuously through the consumed check alone.
kill_agent "$SC" "$BC"
check "quitting clears the way for a fresh recording" 'wait_for 10 entry_gone "$BC"' "$(cat "$CACHE/recorder.json" 2>/dev/null)"
R send -s "$SC" -b "$BC" 'claude'$'\r'
check "recorded again" 'wait_for 20 recorded_as "$BC" claude' "$(cat "$CACHE/recorder.json" 2>/dev/null)"
# The new conversation's self-report must land in sessions.tsv before
# its ref is read: the report races the recording, and a ref read too
# early still names the previous conversation — one this log already
# holds a --resume run for, which the checks below would count as a
# resume that never happened.
wait_for 10 '[ -n "$(ref_of "$BC")" ] && [ "$(ref_of "$BC")" != "$RB1" ]'
RC1="$(ref_of "$BC")"
kill_agent "$SQ" "$BQ"
wait_for 10 entry_gone "$BQ"
R send -s "$SQ" -b "$BQ" 'claude'$'\r'
wait_for 20 recorded_as "$BQ" claude
wait_for 10 '[ -n "$(ref_of "$BQ")" ] && [ "$(ref_of "$BQ")" != "$RB2" ]'
RC2="$(ref_of "$BQ")"

MARK="$(run_lines)"
stop_server
start_server REX_AGENT_RESUME=0
echo "== generation C: REX_AGENT_RESUME=0"
sleep 8  # past the point any delivery would have landed
check "nothing resumes while disabled" '[ "$(run_lines)" -eq "$MARK" ]' "before=$MARK now=$(run_lines)"
check "the recorded conversations stayed unresumed" \
    '! log_has "claude run args=[--resume $RC1]" && ! log_has "claude run args=[--resume $RC2]"' "$(tail -5 "$LOG")"
check "the panes sit at their shells" 'wait_for 15 at_prompt "$SC" "$BC" && at_prompt "$SQ" "$BQ"' "$(cap "$SC" "$BC" | tail -2)"
check "the recordings are left in place (the recorder never ran)" 'has_entry "$BC" && has_entry "$BQ"' "$(cat "$CACHE/recorder.json" 2>/dev/null)"
check "the manual actions stay unregistered" '! R actions 2>/dev/null | grep -q agent_resume_now' "$(R actions 2>/dev/null | grep -c agent_resume)"

# Isolation: a cache that was absent before the run must still be absent
# after it, or the sandbox leaked into the real one. (A cache that was
# already present belongs to real use and is left alone by this check.)
check "the real ~/.cache/rex-agent-resume was never created" \
    '[ "$REAL_CACHE_BEFORE" = present ] || [ ! -e "$REAL_CACHE" ]' \
    "before=$REAL_CACHE_BEFORE now=$(ls -la "$HOME/.cache" 2>/dev/null | grep rex)"

echo
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
