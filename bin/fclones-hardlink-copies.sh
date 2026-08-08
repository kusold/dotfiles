#!/usr/bin/env bash
set -Eeuo pipefail

umask 0027

# Use one fclones-native brace glob for compatibility with releases where
# --name consumes only one argument. Multiple bare patterns would otherwise be
# interpreted as input paths relative to the script's working directory.
VIDEO_PATTERN="*.{mkv,mp4,m4v,avi,ts,m2ts}"

APPLY=false
ASSUME_YES=false
ENV_FILE=""
GENERATE_ENV_FILE=""

usage() {
    cat <<'EOF'
Usage: fclones-hardlink-copies.sh [--env-file PATH] [--apply] [--yes]
       fclones-hardlink-copies.sh --generate-env-file PATH

Without --apply, regenerate the duplicate report and write a hardlink dry-run.
With --apply, do the same checks and then replace duplicate files under COPIES
with hardlinks to matching files under ORIGINALS.

Options:
  --env-file PATH          Load configuration from an absolute-path dotenv file.
  --generate-env-file PATH Write a sample env file and exit without running fclones.
  --apply                  Perform the hardlink conversion after generating the dry-run.
  --yes                    Skip the interactive confirmation; valid only with --apply.
  -h, --help

The env file accepts KEY=VALUE or export KEY=VALUE assignments. Values may be
unquoted or enclosed in matching single or double quotes. Shell expansion and
commands are not evaluated. Blank lines and lines beginning with # are ignored.

Environment overrides:
  FCLONES_BIN
  ORIGINALS
  COPIES
  FCLONES_REPORT_DIR
  FCLONES_LOG_DIR
  FCLONES_CACHE_DIR       Set to an empty string to disable the hash cache.
  FCLONES_LOCK_FILE
  FCLONES_HASH_FUNCTION
  FCLONES_RETENTION_DAYS  Days to retain reports and logs; 0 keeps them forever.
  FCLONES_HEALTHCHECK_URL Optional Healthchecks.io-compatible base ping URL.

When FCLONES_HEALTHCHECK_URL is set, the script requests URL/start when work
begins and URL/<exit-code> when it finishes. Ping failures are logged as
warnings and do not change the script's exit code.
EOF
}

set_config_defaults() {
    if [[ "${1:-}" == "--reset" ]]; then
        unset FCLONES_BIN ORIGINALS COPIES FCLONES_REPORT_DIR FCLONES_LOG_DIR \
            FCLONES_CACHE_DIR FCLONES_LOCK_FILE FCLONES_HASH_FUNCTION \
            FCLONES_RETENTION_DAYS FCLONES_HEALTHCHECK_URL
    fi

    FCLONES_BIN="${FCLONES_BIN:-fclones}"
    ORIGINALS="${ORIGINALS:-/mnt/tank/red/Media/originals}"
    COPIES="${COPIES:-/mnt/tank/red/Media/media/copies}"
    FCLONES_REPORT_DIR="${FCLONES_REPORT_DIR:-/mnt/tank/red/Replaceable/Application-Cache/fclones}"
    FCLONES_LOG_DIR="${FCLONES_LOG_DIR:-${FCLONES_REPORT_DIR}/logs}"
    FCLONES_CACHE_DIR="${FCLONES_CACHE_DIR-${FCLONES_REPORT_DIR}/cache}"
    FCLONES_LOCK_FILE="${FCLONES_LOCK_FILE:-${FCLONES_REPORT_DIR}/fclones-hardlink-copies.lock}"
    FCLONES_HASH_FUNCTION="${FCLONES_HASH_FUNCTION:-blake3}"
    FCLONES_RETENTION_DAYS="${FCLONES_RETENTION_DAYS:-30}"
    FCLONES_HEALTHCHECK_URL="${FCLONES_HEALTHCHECK_URL:-}"
}

generate_env_file() {
    local output_path="$1"

    [[ -n "$output_path" ]] || die "--generate-env-file requires a path"
    [[ ! -e "$output_path" && ! -L "$output_path" ]] || die "refusing to overwrite existing path: $output_path"

    set_config_defaults --reset

    if ! (set -o noclobber; cat >"$output_path" <<EOF
# Configuration for fclones-hardlink-copies.sh.
# Adjust these paths for the host before running the script.
FCLONES_BIN=$FCLONES_BIN
ORIGINALS=$ORIGINALS
COPIES=$COPIES
FCLONES_REPORT_DIR=$FCLONES_REPORT_DIR
FCLONES_LOG_DIR=$FCLONES_LOG_DIR
# Set FCLONES_CACHE_DIR to an empty string to disable the hash cache.
FCLONES_CACHE_DIR=$FCLONES_CACHE_DIR
FCLONES_LOCK_FILE=$FCLONES_LOCK_FILE
FCLONES_HASH_FUNCTION=$FCLONES_HASH_FUNCTION
# Set FCLONES_RETENTION_DAYS to 0 to keep reports and logs forever.
FCLONES_RETENTION_DAYS=$FCLONES_RETENTION_DAYS
# Optional Healthchecks.io-compatible base ping URL. Treat this value as a secret.
FCLONES_HEALTHCHECK_URL=$FCLONES_HEALTHCHECK_URL
EOF
    ); then
        die "could not write sample env file: $output_path"
    fi

    printf 'Wrote sample env file: %s\n' "$output_path"
}

log() {
    printf '[%(%Y-%m-%d %H:%M:%S)T] %s\n' -1 "$*"
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

trim_whitespace() {
    local value="$1"

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

load_env_file() {
    local env_file="$1"
    local line line_number=0 name value

    [[ "$env_file" == /* ]] || die "--env-file requires an absolute path"
    [[ -f "$env_file" ]] || die "env file does not exist: $env_file"
    [[ -r "$env_file" ]] || die "env file is not readable: $env_file"

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_number += 1))
        line="${line%$'\r'}"

        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        if [[ ! "$line" =~ ^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            die "invalid env assignment at $env_file:$line_number"
        fi

        name="${BASH_REMATCH[2]}"
        value="$(trim_whitespace "${BASH_REMATCH[3]}")"

        if [[ "$value" == \"* || "$value" == \'* ]]; then
            if [[ ${#value} -lt 2 || "${value: -1}" != "${value:0:1}" ]]; then
                die "unmatched quote at $env_file:$line_number"
            fi
            value="${value:1:${#value}-2}"
        fi

        case "$name" in
            FCLONES_BIN | ORIGINALS | COPIES | FCLONES_REPORT_DIR | FCLONES_LOG_DIR | \
                FCLONES_CACHE_DIR | FCLONES_LOCK_FILE | FCLONES_HASH_FUNCTION | \
                FCLONES_RETENTION_DAYS | FCLONES_HEALTHCHECK_URL)
                printf -v "$name" '%s' "$value"
                ;;
            *)
                die "unsupported variable $name at $env_file:$line_number"
                ;;
        esac
    done <"$env_file"
}

cleanup_old_files() {
    local directory="$1"
    local pattern="$2"

    ((FCLONES_RETENTION_DAYS > 0)) || return 0
    find "$directory" -maxdepth 1 -type f -name "$pattern" \
        -mmin "+$((FCLONES_RETENTION_DAYS * 24 * 60))" -delete
}

log_exit() {
    local exit_code="$1"

    log "Finished with exit code $exit_code after $((SECONDS - START_SECONDS)) seconds"
}

healthcheck_endpoint() {
    local suffix="$1"
    local base_url query_string=""

    base_url="$FCLONES_HEALTHCHECK_URL"
    if [[ "$base_url" == *\?* ]]; then
        query_string="?${base_url#*\?}"
        base_url="${base_url%%\?*}"
    fi

    printf '%s/%s%s' "${base_url%/}" "$suffix" "$query_string"
}

report_healthcheck() {
    local event="$1"
    local endpoint

    [[ -n "$FCLONES_HEALTHCHECK_URL" ]] || return 0
    endpoint="$(healthcheck_endpoint "$event")"

    # Monitoring must not delay or change the result of the actual job. Keep
    # requests bounded, retry transient failures, and reduce any curl failure
    # to a warning without printing the secret ping URL.
    if ! curl --fail --silent --show-error --max-time 10 --retry 3 \
        --retry-delay 1 --proto '=http,https' --output /dev/null -- "$endpoint" \
        >/dev/null 2>&1; then
        log "warning: healthcheck $event ping failed" >&2
    fi
}

handle_exit() {
    local exit_code="$1"

    trap - EXIT
    log_exit "$exit_code"
    report_healthcheck "$exit_code"
    exit "$exit_code"
}

while (($# > 0)); do
    case "$1" in
        --apply)
            APPLY=true
            ;;
        --yes)
            ASSUME_YES=true
            ;;
        --env-file)
            shift
            (($# > 0)) || die "--env-file requires a path"
            [[ -z "$ENV_FILE" ]] || die "--env-file may only be specified once"
            ENV_FILE="$1"
            ;;
        --env-file=*)
            [[ -z "$ENV_FILE" ]] || die "--env-file may only be specified once"
            ENV_FILE="${1#*=}"
            [[ -n "$ENV_FILE" ]] || die "--env-file requires a path"
            ;;
        --generate-env-file)
            shift
            (($# > 0)) || die "--generate-env-file requires a path"
            [[ -z "$GENERATE_ENV_FILE" ]] || die "--generate-env-file may only be specified once"
            GENERATE_ENV_FILE="$1"
            [[ -n "$GENERATE_ENV_FILE" ]] || die "--generate-env-file requires a path"
            ;;
        --generate-env-file=*)
            [[ -z "$GENERATE_ENV_FILE" ]] || die "--generate-env-file may only be specified once"
            GENERATE_ENV_FILE="${1#*=}"
            [[ -n "$GENERATE_ENV_FILE" ]] || die "--generate-env-file requires a path"
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            die "unknown argument: $1"
            ;;
    esac
    shift
done

if [[ -n "$GENERATE_ENV_FILE" ]]; then
    if [[ -n "$ENV_FILE" || "$APPLY" == true || "$ASSUME_YES" == true ]]; then
        die "--generate-env-file cannot be combined with --env-file, --apply, or --yes"
    fi
    generate_env_file "$GENERATE_ENV_FILE"
    exit 0
fi

if [[ -n "$ENV_FILE" ]]; then
    load_env_file "$ENV_FILE"
fi

set_config_defaults

if [[ "$ASSUME_YES" == true && "$APPLY" != true ]]; then
    die "--yes requires --apply"
fi

if ((EUID != 0)); then
    die "run this script as root (for example, with sudo)"
fi

command -v "$FCLONES_BIN" >/dev/null 2>&1 || die "fclones executable not found: $FCLONES_BIN"
command -v flock >/dev/null 2>&1 || die "flock is required for single-instance execution"
command -v tee >/dev/null 2>&1 || die "tee is required for persistent logging"
if [[ -n "$FCLONES_HEALTHCHECK_URL" ]]; then
    command -v curl >/dev/null 2>&1 || die "curl is required when FCLONES_HEALTHCHECK_URL is set"
    [[ "$FCLONES_HEALTHCHECK_URL" =~ ^https?://[^[:space:]]+$ ]] || \
        die "FCLONES_HEALTHCHECK_URL must be an HTTP or HTTPS URL without whitespace"
fi

[[ "$FCLONES_RETENTION_DAYS" =~ ^[0-9]+$ ]] || die "FCLONES_RETENTION_DAYS must be a non-negative integer"

ORIGINALS="${ORIGINALS%/}"
COPIES="${COPIES%/}"

[[ -n "$ORIGINALS" && "$ORIGINALS" != "/" ]] || die "refusing unsafe ORIGINALS path"
[[ -n "$COPIES" && "$COPIES" != "/" ]] || die "refusing unsafe COPIES path"
[[ "$ORIGINALS" != "$COPIES" ]] || die "ORIGINALS and COPIES must be different paths"
[[ -d "$ORIGINALS" ]] || die "ORIGINALS directory does not exist: $ORIGINALS"
[[ -d "$COPIES" ]] || die "COPIES directory does not exist: $COPIES"

ORIGINALS_DEVICE="$(stat -c '%d' -- "$ORIGINALS")"
COPIES_DEVICE="$(stat -c '%d' -- "$COPIES")"
if [[ "$ORIGINALS_DEVICE" != "$COPIES_DEVICE" ]]; then
    die "hardlinks cannot cross filesystems (ORIGINALS device $ORIGINALS_DEVICE, COPIES device $COPIES_DEVICE)"
fi

install -d -m 0750 -- "$FCLONES_REPORT_DIR" "$FCLONES_LOG_DIR"
if [[ -n "$FCLONES_CACHE_DIR" ]]; then
    install -d -m 0750 -- "$FCLONES_CACHE_DIR"
fi

# Prevent cron from starting another scan while an earlier run is still active.
exec {LOCK_FD}>"$FCLONES_LOCK_FILE"
flock -n "$LOCK_FD" || die "another fclones-hardlink-copies.sh run is already active"

RUN_TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
GROUP_REPORT="${FCLONES_REPORT_DIR}/duplicate-groups-${RUN_TIMESTAMP}.txt"
DRY_RUN_REPORT="${FCLONES_REPORT_DIR}/hardlink-dry-run-${RUN_TIMESTAMP}.txt"
RUN_LOG="${FCLONES_LOG_DIR}/fclones-hardlink-copies-${RUN_TIMESTAMP}.log"
START_SECONDS=$SECONDS

exec > >(tee -a -- "$RUN_LOG") \
    2> >(tee -a -- "$RUN_LOG" >&2)
trap 'handle_exit "$?"' EXIT

# Healthchecks.io-style endpoints use /start for the beginning of a run and
# /<exit-code> for completion, where zero is success and non-zero is failure.
report_healthcheck start

cleanup_old_files "$FCLONES_REPORT_DIR" 'duplicate-groups-*.txt'
cleanup_old_files "$FCLONES_REPORT_DIR" 'hardlink-dry-run-*.txt'
cleanup_old_files "$FCLONES_LOG_DIR" 'fclones-hardlink-copies-*.log'

# BLAKE3 is a 256-bit cryptographic hash that is fast and parallelizable on
# large files. It gives substantially stronger collision resistance than
# fclones' non-cryptographic MetroHash default without imposing SHA-256's
# throughput cost on a large media library.
GROUP_ARGS=(
    group
    --one-fs
    --no-ignore
    --hidden
    --hash-fn "$FCLONES_HASH_FUNCTION"
)

# A persistent cache avoids re-hashing unchanged files on each cron run. fclones
# validates cached entries using inode, size, and modification-time metadata.
if [[ -n "$FCLONES_CACHE_DIR" ]]; then
    GROUP_ARGS+=(--cache "$FCLONES_CACHE_DIR")
fi

GROUP_ARGS+=(
    --name "$VIDEO_PATTERN"
    --output "$GROUP_REPORT"
    "$ORIGINALS"
    "$COPIES"
)

# Group without --isolate so paths that are already hardlinked resolve to one
# inode and are omitted. Apply isolation only during linking so duplicates
# found solely within ORIGINALS or solely within COPIES are left untouched.
LINK_SCOPE_ARGS=(
    --isolate "$ORIGINALS"
    --isolate "$COPIES"
    --keep-path "$ORIGINALS/**"
    --path "$COPIES/**"
)

log "Grouping matching files"
log "ORIGINALS: $ORIGINALS"
log "COPIES:    $COPIES"
if [[ -n "$ENV_FILE" ]]; then
    log "Env file:  $ENV_FILE"
fi
log "Log:       $RUN_LOG"
"$FCLONES_BIN" "${GROUP_ARGS[@]}" </dev/null

log "Generating hardlink dry-run: $DRY_RUN_REPORT"
"$FCLONES_BIN" link \
    --dry-run \
    "${LINK_SCOPE_ARGS[@]}" \
    --output "$DRY_RUN_REPORT" \
    <"$GROUP_REPORT"

if [[ "$APPLY" != true ]]; then
    log "No files changed. Review $DRY_RUN_REPORT, then rerun with --apply."
    exit 0
fi

if [[ "$ASSUME_YES" != true ]]; then
    printf '\nThis will replace duplicate files under:\n  %s\n' "$COPIES"
    printf 'Files under this path will not be replaced or removed:\n  %s\n' "$ORIGINALS"
    printf 'Pause applications that import, rename, or delete these files before continuing.\n'
    read -r -p 'Type APPLY to continue: ' CONFIRMATION </dev/tty
    [[ "$CONFIRMATION" == "APPLY" ]] || die "confirmation not received"
fi

log "Replacing duplicate files under COPIES with hardlinks"
"$FCLONES_BIN" link \
    "${LINK_SCOPE_ARGS[@]}" \
    <"$GROUP_REPORT"

log "Hardlink conversion complete"
