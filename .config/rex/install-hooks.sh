#!/bin/sh
# Detect installed coding agents (claude, codex, pi) and install the
# self-report hooks that let a restored Rex terminal resume the exact
# conversation that ran in it. Run with --ensure (the default, from
# init.lua at server start) it rewrites the managed entry idempotently,
# which also repairs an entry an older version of this script left in a
# different shape; run with --status it reports and changes nothing.
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

say() { printf 'install-hooks: %s\n' "$1"; }

# merge_json <file> <command> <matcher|->:
# rewrite our managed hook entry, preserve everything else. Both claude's
# settings.json and codex's hooks.json nest event keys under a top-level
# "hooks" object.
merge_json() {
    python3 - "$1" "$2" "$3" <<'EOF'
import json, os, sys
path, command, matcher = sys.argv[1], sys.argv[2], sys.argv[3]
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
# Migrate the shape an earlier version of this script wrote for codex:
# a top-level "SessionStart" instead of one under "hooks". Codex ignores
# (or rejects) that shape, so the hook never fired. Only drop it when
# every entry in it is ours.
top = doc.get("SessionStart")
if isinstance(top, list) and top and all(
        isinstance(e, dict) and any(
            marker in str(h.get("command", ""))
            for h in e.get("hooks", []) if isinstance(h, dict))
        for e in top):
    del doc["SessionStart"]
outer = doc.setdefault("hooks", {})
if not isinstance(outer, dict):
    print(f"install-hooks: {path}: hooks is not an object")
    sys.exit(1)
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
# A trailing comment on the header is legal TOML and must still count as
# the section, or a second [features] table would be appended below.
m = re.search(r"(?m)^\[features\][ \t]*(?:#.*)?$", s)
section = re.search(r"(?ms)^\[features\][ \t]*(?:#.*)?$(.*?)(?=^\[|\Z)", s)
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
    if [ "$mode" = status ]; then
        if has_hook "$settings"; then
            say "claude: hook installed"
        else
            say "claude: not installed"
        fi
    elif command -v python3 >/dev/null 2>&1; then
        # Always re-merge: it is idempotent, and it also repairs or
        # upgrades an entry an older version of this script wrote.
        merge_json "$settings" "$cmd" '^(startup|resume|clear|compact|fork)$' \
            && say "claude: hook installed in $settings"
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
    if [ "$mode" = status ]; then
        if has_hook "$hooks_json"; then
            say "codex: hook installed"
        else
            say "codex: not installed"
        fi
    elif command -v python3 >/dev/null 2>&1; then
        merge_json "$hooks_json" "$cmd" - \
            && say "codex: hook installed in $hooks_json"
    else
        say "codex: python3 missing, skipped"
    fi
    if [ "$mode" != status ]; then
        toml="$codex_dir/config.toml"
        # fix_toml is idempotent and exits before writing when
        # [features] already sets hooks = true. A grep fast path would
        # false-positive on a same-named key in any other section.
        if { [ -f "$toml" ] || [ -f "$hooks_json" ]; } \
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
            && say "pi: extension installed in $dest"
    fi
else
    [ "$mode" = status ] && say "pi: not found"
fi

exit 0
