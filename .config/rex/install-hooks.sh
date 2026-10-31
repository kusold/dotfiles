#!/bin/sh
# Detect installed coding agents (claude, codex, pi) and install the
# self-report hooks that let a restored Rex terminal resume the exact
# conversation that ran in it. Run with --ensure (the default, from the
# shell startup hooks) it only writes when something is missing or
# outdated; run with --status it reports and changes nothing.
#
# What it touches, honoring each agent's config override:
#   claude  $CLAUDE_CONFIG_DIR (default ~/.claude)      settings.json
#   codex   $CODEX_HOME       (default ~/.codex)        hooks.json + config.toml
#   pi      $PI_CODING_AGENT_DIR (default ~/.pi/agent)  extensions/
#
# Managed entries are recognized by the rex-agent-state path in their
# command; everything else in those files is preserved. Requires
# python3 for the JSON/TOML edits; agents are skipped without it.

set -u

hooks_dir="$HOME/.config/rex/hooks"
hook_sh="$hooks_dir/rex-agent-state.sh"
hook_ts="$hooks_dir/rex-agent-state.ts"
marker="rex-agent-state"

mode=ensure
[ "${1:-}" = "--status" ] && mode=status
changed=0

say() { printf 'install-hooks: %s\n' "$1"; }

# merge_json <file> <command> <matcher|-> <wrap|top>:
# rewrite our managed hook entry, preserve everything else. Claude's
# settings.json nests under "hooks"; codex's hooks.json is top-level.
merge_json() {
    python3 - "$1" "$2" "$3" "$4" <<'EOF'
import json, os, sys
path, command, matcher, wrap = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
marker = "rex-agent-state"
if matcher == "-":
    matcher = None
try:
    with open(path) as f:
        doc = json.load(f)
except FileNotFoundError:
    doc = {}
except Exception:
    print(f"install-hooks: {path}: unparseable JSON, leaving it alone")
    sys.exit(1)
if not isinstance(doc, dict):
    print(f"install-hooks: {path}: unexpected JSON shape, leaving it alone")
    sys.exit(1)
if wrap == "hooks":
    outer = doc.setdefault("hooks", {})
    if not isinstance(outer, dict):
        print(f"install-hooks: {path}: hooks is not an object")
        sys.exit(1)
else:
    outer = doc
arr = outer.setdefault("SessionStart", [])
if not isinstance(arr, list):
    print(f"install-hooks: {path}: SessionStart is not a list")
    sys.exit(1)
ours = {"hooks": [{"type": "command", "command": command, "timeout": 10}]}
if matcher:
    ours = {"matcher": matcher, **ours}
kept = [e for e in arr
        if not (isinstance(e, dict) and any(
            marker in str(h.get("command", "")) for h in e.get("hooks", [])
            if isinstance(h, dict)))]
kept.append(ours)
outer["SessionStart"] = kept
tmp = path + ".rex-install.tmp"
with open(tmp, "w") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
os.replace(tmp, path)
EOF
}

# has_hook <json file> : does a managed entry exist already?
has_hook() {
    grep -q "$marker" "$1" 2>/dev/null
}

# fix_toml <config.toml> : set [features] hooks = true, preserving rest.
fix_toml() {
    python3 - "$1" <<'EOF'
import re, sys
path = sys.argv[1]
try:
    s = open(path).read()
except FileNotFoundError:
    s = ""
m = re.search(r"(?m)^\[features\][ \t]*$", s)
section = re.search(r"(?ms)^\[features\][ \t]*$(.*?)(?=^\[|\Z)", s)
if section and re.search(r"(?m)^\s*hooks\s*=\s*true\s*$", section.group(1)):
    sys.exit(0)
if section:
    block = section.group(1)
    if re.search(r"(?m)^\s*hooks\s*=", block):
        new = re.sub(r"(?m)^(\s*hooks\s*=\s*).*$", r"\1true", block, count=1)
        s = s[:section.start(1)] + new + s[section.end(1):]
    else:
        at = m.end()
        s = s[:at] + "\nhooks = true" + s[at:]
else:
    s = s.rstrip("\n") + ("\n" if s else "") + "\n[features]\nhooks = true\n"
if not s.endswith("\n"):
    s += "\n"
tmp = path + ".rex-install.tmp"
open(tmp, "w").write(s)
import os; os.replace(tmp, path)
EOF
}

# --- claude -----------------------------------------------------------------
claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
if [ -d "$claude_dir" ]; then
    settings="$claude_dir/settings.json"
    cmd="bash '$hook_sh' claude"
    if has_hook "$settings"; then
        [ "$mode" = status ] && say "claude: hook installed"
    elif [ "$mode" = status ]; then
        say "claude: not installed"
    elif command -v python3 >/dev/null 2>&1; then
        merge_json "$settings" "$cmd" '^(startup|resume|clear|compact|fork)$' hooks \
            && say "claude: hook installed in $settings" && changed=1
    else
        say "claude: python3 missing, skipped"
    fi
else
    [ "$mode" = status ] && say "claude: not found"
fi

# --- codex ------------------------------------------------------------------
codex_dir="${CODEX_HOME:-$HOME/.codex}"
if [ -d "$codex_dir" ]; then
    hooks_json="$codex_dir/hooks.json"
    cmd="bash '$hook_sh' codex"
    if has_hook "$hooks_json"; then
        [ "$mode" = status ] && say "codex: hook installed"
    elif [ "$mode" != status ]; then
        if command -v python3 >/dev/null 2>&1; then
            merge_json "$hooks_json" "$cmd" - top \
                && say "codex: hook installed in $hooks_json" && changed=1
        else
            say "codex: python3 missing, skipped"
        fi
    else
        say "codex: not installed"
    fi
    if [ "$mode" != status ]; then
        toml="$codex_dir/config.toml"
        # Fast path: python3 only when the setting is actually missing.
        if ! grep -q 'hooks *= *true' "$toml" 2>/dev/null \
            && { [ -f "$toml" ] || [ -f "$hooks_json" ]; } \
            && command -v python3 >/dev/null 2>&1; then
            fix_toml "$toml"
        fi
    elif ! grep -Eq '^\[features\][^]]*$' "$codex_dir/config.toml" 2>/dev/null \
        || ! grep -q 'hooks *= *true' "$codex_dir/config.toml" 2>/dev/null; then
        say "codex: features.hooks not enabled"
    fi
else
    [ "$mode" = status ] && say "codex: not found"
fi

# --- pi ---------------------------------------------------------------------
pi_dir="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
if [ -d "$pi_dir" ]; then
    dest="$pi_dir/extensions/$(basename "$hook_ts")"
    if [ -f "$dest" ] && cmp -s "$hook_ts" "$dest"; then
        [ "$mode" = status ] && say "pi: extension installed"
    elif [ "$mode" = status ]; then
        say "pi: extension not installed"
    else
        mkdir -p "$pi_dir/extensions" 2>/dev/null \
            && cp "$hook_ts" "$dest" \
            && say "pi: extension installed in $dest" && changed=1
    fi
else
    [ "$mode" = status ] && say "pi: not found"
fi

exit 0
