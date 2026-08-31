#!/usr/bin/env bash
set -euo pipefail

# ── Usage ──────────────────────────────────────────────────────────────────
usage() {
    cat <<'EOF'
Usage: $(basename "$0") [OPTIONS]

Deploy the Agent Framework (AF) into a target project.

Supports two use cases:
  UC1 (one-time): Run once to install AF into a project.
  UC2 (coupled):  Re-run to sync updates from AF source to project.

The .af-manifest supports annotations:
  [customizable] -- file contains project-specific content; protected on update
  [optional]     -- directory may not exist in AF source; no warning if missing
  [vscode]       -- file deployed to .vscode/ instead of .github/

Customizable files are protected on update. When AF has changes to a
customizable file, a PROTECT message with "review manually" guidance is
shown. Use --force to overwrite.

An ephemeral backup directory (.af-backup-{timestamp}) is created before
files are overwritten. If no conflicts remain after deploy, the backup is
automatically deleted. If conflicts exist, the backup persists for manual
recovery.

Backup prune retention precedence:
    CLI flag --backup-prune-days > af-env.conf BACKUP_PRUNE_DAYS > default 14.

Options:
  -t, --target DIR       Project root (default: parent of AF directory)
  -n, --dry-run          Show what would be copied without making changes
  -d, --diff             Compare AF source against deployed copy
  -f, --force            Overwrite customizable files
  -u, --update-hashes    Write baseline hashes from current AF source
    -p, --preflight        Run integrity preflight checks (non-blocking)
    -r, --require-preflight Run integrity preflight checks and block on failure
    -m, --preflight-mode MODE  quick|full (default: quick)
    -b, --backup-prune-days DAYS  Delete stale .af-backup-* older than DAYS (default: 14, 0=off)
  -h, --help             Show this help
EOF
    exit 0
}

# ── Parse arguments ────────────────────────────────────────────────────────
TARGET_DIR=""
DRY_RUN=false
DIFF_MODE=false
FORCE=false
UPDATE_HASHES=false
PREFLIGHT=false
REQUIRE_PREFLIGHT=false
PREFLIGHT_MODE="quick"
BACKUP_PRUNE_DAYS=""
BACKUP_PRUNE_DAYS_CLI=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -t|--target)        TARGET_DIR="$2"; shift 2 ;;
        -n|--dry-run)       DRY_RUN=true; shift ;;
        -d|--diff)          DIFF_MODE=true; shift ;;
        -f|--force)         FORCE=true; shift ;;
        -u|--update-hashes) UPDATE_HASHES=true; shift ;;
        -p|--preflight)     PREFLIGHT=true; shift ;;
        -r|--require-preflight) REQUIRE_PREFLIGHT=true; shift ;;
        -m|--preflight-mode) PREFLIGHT_MODE="$2"; shift 2 ;;
        -b|--backup-prune-days) BACKUP_PRUNE_DAYS="$2"; BACKUP_PRUNE_DAYS_CLI=true; shift 2 ;;
        -h|--help)          usage ;;
        *)                  echo "Unknown option: $1" >&2; usage ;;
    esac
done

case "$PREFLIGHT_MODE" in
    quick|full) ;;
    *) echo "Error: --preflight-mode must be quick|full" >&2; exit 1 ;;
esac

# ── Configuration ──────────────────────────────────────────────────────────
AF_ROOT="$(cd "$(dirname "$0")" && pwd)"
SOURCE_GITHUB="$AF_ROOT/.github"
SOURCE_VSCODE="$AF_ROOT/.vscode"
MANIFEST_PATH="$SOURCE_GITHUB/.af-manifest"
VERSION_PATH="$AF_ROOT/VERSION"

# ── Resolve paths ──────────────────────────────────────────────────────────
if [[ -z "$TARGET_DIR" ]]; then
    TARGET_DIR="$(dirname "$AF_ROOT")"
fi
if [[ ! -d "$TARGET_DIR" ]]; then
    echo "Error: Target directory not found: $TARGET_DIR" >&2
    exit 1
fi
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

TARGET_GITHUB="$TARGET_DIR/.github"
TARGET_VSCODE="$TARGET_DIR/.vscode"
TARGET_AF_ENV="$TARGET_GITHUB/af-env.conf"
# Captured before anything is written. After deployment the file always exists,
# so this is the only moment at which "the target had no AF config" is knowable
# -- and it decides whether the project context budgets are AF's shipped
# placeholders (seed over them) or a baseline someone chose (leave alone).
AF_ENV_WAS_ABSENT=0
[[ -f "$TARGET_AF_ENV" ]] || AF_ENV_WAS_ABSENT=1

get_af_env_value() {
    local key="$1"
    local default_val="${2:-}"
    if [[ ! -f "$TARGET_AF_ENV" ]]; then
        echo "$default_val"
        return
    fi
    local line
    line="$(grep -E "^${key}=" "$TARGET_AF_ENV" | head -1 || true)"
    if [[ -z "$line" ]]; then
        echo "$default_val"
        return
    fi
    echo "${line#*=}" | xargs
}

resolve_backup_prune_days() {
    local default_days=14
    if [[ "$BACKUP_PRUNE_DAYS_CLI" == "true" ]]; then
        echo "$BACKUP_PRUNE_DAYS"
        return
    fi

    local from_conf
    from_conf="$(get_af_env_value BACKUP_PRUNE_DAYS "")"
    if [[ "$from_conf" =~ ^[0-9]+$ ]]; then
        echo "$from_conf"
        return
    fi

    echo "$default_days"
}

target_is_git_repo() {
    local repo_dir="$1"
    command -v git >/dev/null 2>&1 || return 1
    git -C "$repo_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

get_current_git_branch() {
    local repo_dir="$1"
    if ! command -v git >/dev/null 2>&1; then
        echo ""
        return
    fi
    # Outside a repo this exits 128, which `set -e` turned into a silent abort (#244).
    git -C "$repo_dir" branch --show-current 2>/dev/null | tr -d '[:space:]' || true
}

# ── Read versions ──────────────────────────────────────────────────────────
AF_VERSION="unknown"
if [[ -f "$VERSION_PATH" ]]; then
    AF_VERSION="$(tr -d '[:space:]' < "$VERSION_PATH")"
fi

DEPLOYED_VERSION_FILE="$TARGET_GITHUB/.af-version"
DEPLOYED_INFO=""
if [[ -f "$DEPLOYED_VERSION_FILE" ]]; then
    DEPLOYED_INFO="$(head -1 "$DEPLOYED_VERSION_FILE")"
fi

# ── Parse manifest with annotations ───────────────────────────────────────
# Format: path  [annotation1, annotation2]
#   [customizable] — project may modify; protected on update
#   [optional]     — may not exist in AF source; no warning if missing
#   [vscode]       — deployed to .vscode/ instead of .github/

if [[ ! -f "$MANIFEST_PATH" ]]; then
    echo "Error: .af-manifest not found at: $MANIFEST_PATH" >&2
    exit 1
fi

MANIFEST_DIRS=()
MANIFEST_FILES=()
MANIFEST_ROOT_FILES=()
MANIFEST_VSCODE_FILES=()
declare -A CUSTOMIZABLE_MAP
declare -A OPTIONAL_DIR_MAP
declare -A OPTIONAL_FILE_MAP

while IFS= read -r raw_line; do
    line="$(echo "$raw_line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$line" || "$line" == \#* ]] && continue

    # Parse annotations from end of line: path  [ann1, ann2]
    annotations=""
    entry_path="$line"
    if [[ "$line" =~ ^(.+)[[:space:]]+\[(.+)\][[:space:]]*$ ]]; then
        entry_path="$(echo "${BASH_REMATCH[1]}" | sed 's/[[:space:]]*$//')"
        annotations="${BASH_REMATCH[2]}"
    fi

    is_vscode=false
    is_customizable=false
    is_optional=false

    if [[ -n "$annotations" ]]; then
        IFS=',' read -ra ann_parts <<< "$annotations"
        for ann in "${ann_parts[@]}"; do
            ann="$(echo "$ann" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')"
            case "$ann" in
                vscode)       is_vscode=true ;;
                customizable) is_customizable=true ;;
                optional)     is_optional=true ;;
            esac
        done
    fi

    if [[ "$entry_path" == */ ]]; then
        dir_name="${entry_path%/}"
        MANIFEST_DIRS+=("$dir_name")
        if $is_optional; then
            OPTIONAL_DIR_MAP["$dir_name"]=1
        fi
    elif $is_vscode; then
        MANIFEST_VSCODE_FILES+=("$entry_path")
        if $is_optional; then
            OPTIONAL_FILE_MAP["$entry_path"]=1
        fi
    else
        MANIFEST_FILES+=("$entry_path")
        if $is_optional; then
            OPTIONAL_FILE_MAP["$entry_path"]=1
        fi
    fi

    if $is_customizable; then
        if $is_vscode; then
            CUSTOMIZABLE_MAP["vscode/$entry_path"]=1
        else
            CUSTOMIZABLE_MAP["$entry_path"]=1
        fi
    fi
done < "$MANIFEST_PATH"

# Filter root files: exclude files within manifest directories
for f in "${MANIFEST_FILES[@]}"; do
    in_dir=false
    for d in "${MANIFEST_DIRS[@]}"; do
        if [[ "$f" == "$d/"* ]]; then
            in_dir=true
            break
        fi
    done
    if ! $in_dir; then
        MANIFEST_ROOT_FILES+=("$f")
    fi
done

# ── Manifest validation ───────────────────────────────────────────────────
for dir in "${MANIFEST_DIRS[@]}"; do
    src_dir="$SOURCE_GITHUB/$dir"
    if [[ ! -d "$src_dir" ]] && [[ -z "${OPTIONAL_DIR_MAP[$dir]+x}" ]]; then
        echo "  WARNING: Manifest directory '$dir/' not found in AF source"
    fi
done
for f in "${MANIFEST_ROOT_FILES[@]}"; do
    src="$SOURCE_GITHUB/$f"
    if [[ ! -f "$src" ]] && [[ -z "${OPTIONAL_FILE_MAP[$f]+x}" ]]; then
        echo "  WARNING: Manifest file '$f' not found in AF source"
    fi
done
for f in "${MANIFEST_VSCODE_FILES[@]}"; do
    src="$SOURCE_VSCODE/$f"
    if [[ ! -f "$src" ]] && [[ -z "${OPTIONAL_FILE_MAP[$f]+x}" ]]; then
        echo "  WARNING: Manifest vscode file '$f' not found in AF source"
    fi
done

# ── Counters ───────────────────────────────────────────────────────────────
STAT_CREATED=0
STAT_UPDATED=0
STAT_UNCHANGED=0
STAT_PROTECTED=0
STAT_CONFLICT=0
STAT_PRESERVED=0
STAT_DEACTIVATED=0
BACKUP_DIR=""
BACKUP_COUNT=0

# ── Helper: is file customizable ──────────────────────────────────────────
is_customizable() {
    [[ -n "${CUSTOMIZABLE_MAP[$1]+x}" ]]
}

# ── Helper: file hash ─────────────────────────────────────────────────────
file_hash() {
    # Uppercase hex to match deploy.ps1 (ToString('X2')) and deploy_core.py
    # (.hexdigest().upper()) so a .af-hashes baseline is byte-portable across all
    # three tools (the MCP/bash 3-way compare is case-sensitive).
    if command -v sha256sum &>/dev/null; then
        sha256sum "$1" | cut -d' ' -f1 | tr 'a-f' 'A-F'
    elif command -v shasum &>/dev/null; then
        shasum -a 256 "$1" | cut -d' ' -f1 | tr 'a-f' 'A-F'
    else
        md5sum "$1" | cut -d' ' -f1 | tr 'a-f' 'A-F'
    fi
}
# ── Agent model tier resolution ────────────────────────────────────────
# Subagent .agent.md files carry a tier placeholder (__AF_TIER_PREMIUM__ etc.)
# resolved at deploy time from the target af-env.conf (AF_MODEL_TIER_*) or the
# curated defaults below. Multiple comma-separated entries become a prioritized
# YAML array (VS Code tries each until available). Keep in sync with deploy.ps1.
declare -A TIER_DEFAULTS=(
    [PREMIUM]='Claude Opus 4.8 (copilot), Claude Opus 4.7 (copilot), Claude Sonnet 5 (copilot)'
    [BALANCED]='Claude Sonnet 5 (copilot), Claude Sonnet 4.6 (copilot), Claude Sonnet 4.5 (copilot)'
    [EFFICIENT]='Claude Haiku 4.5 (copilot), Claude Sonnet 5 (copilot)'
)
tier_yaml() {
    # $1 = tier name; prints a `model:` line or a multi-line YAML array
    local tier="$1" val
    val="$(get_af_env_value "AF_MODEL_TIER_$tier" "")"
    [[ -z "$val" ]] && val="${TIER_DEFAULTS[$tier]}"
    local IFS=',' arr m count=0
    read -ra arr <<< "$val"
    for m in "${arr[@]}"; do
        m="$(printf '%s' "$m" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        [[ -n "$m" ]] && ((count++)) || true
    done
    if [[ $count -le 1 ]]; then
        m="$(printf '%s' "${arr[0]}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        printf 'model: %s' "$m"
    else
        printf 'model:'
        for m in "${arr[@]}"; do
            m="$(printf '%s' "$m" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
            [[ -z "$m" ]] && continue
            printf '\n  - %s' "$m"
        done
    fi
}
has_tier_token() { grep -qE '__AF_TIER_(PREMIUM|BALANCED|EFFICIENT)__' "$1"; }
tier_resolve_file() {
    # $1 = source path; writes resolved content to a new temp file, echoes path
    local src="$1" tmp line stripped cr tier
    tmp="$(mktemp)"
    while IFS= read -r line || [[ -n "$line" ]]; do
        stripped="${line%$'\r'}"; cr=""; [[ "$stripped" != "$line" ]] && cr=$'\r'
        if [[ "$stripped" =~ ^model:[[:space:]]*__AF_TIER_(PREMIUM|BALANCED|EFFICIENT)__[[:space:]]*$ ]]; then
            tier="${BASH_REMATCH[1]}"
            printf '%s\n' "$(tier_yaml "$tier")"
        else
            printf '%s%s\n' "$stripped" "$cr"
        fi
    done < "$src" > "$tmp"
    printf '%s' "$tmp"
}
_strip_bom_cr() {
    # $1 = file; emit contents with a leading UTF-8 BOM removed and all CR dropped.
    # (Scope: the payload is text-only with LF/CRLF endings; classic lone-CR Mac
    # endings and non-UTF-8 text are out of scope and handled verbatim upstream.)
    if [[ "$(head -c3 "$1")" == $'\xEF\xBB\xBF' ]]; then
        tail -c +4 "$1" | tr -d '\r'
    else
        tr -d '\r' < "$1"
    fi
}
# Write canonical deployed bytes of $1 to path $2: UTF-8 no BOM, LF line endings,
# tier tokens resolved. Binary/empty files are copied verbatim. Keeps deploy.sh
# byte-identical to deploy.ps1 and the MCP deploy so switching paths yields no
# spurious EOL diffs. (The framework payload is text-only.)
canonical_write() {
    local src="$1" dest="$2" rtmp
    if ! LC_ALL=C grep -Iq . "$src" 2>/dev/null; then
        cp "$src" "$dest"; return   # binary or empty -- copy verbatim
    fi
    if has_tier_token "$src"; then
        rtmp="$(tier_resolve_file "$src")"
        _strip_bom_cr "$rtmp" > "$dest"; rm -f "$rtmp"
    else
        _strip_bom_cr "$src" > "$dest"
    fi
}
# ── Managed regions (measure #2) ──────────────────────────────────────────
# Byte-parity with deploy_core.py strip_managed_regions/merge_managed_regions
# and deploy.ps1. A deployed file may carry an AF:MANAGED:{name} region whose
# body is project-owned: it is ignored for classification (hash over the
# region-stripped content) and preserved on write (the target's region body is
# transplanted onto the framework base). Region names are ASCII [A-Za-z0-9_.-].
# Used sparingly -- prefer af-env.conf for project-specification whenever
# possible.
#
# VERIFICATION NOTE (measure 2b): the awk region engine below is
# byte-parity-critical and is exercised by tests/test_sh_managed_regions_parity.py,
# which is SKIPPED on hosts without bash/awk (e.g. the Windows dev box where this
# was authored) and runs in Linux CI. Until that CI run is green, no payload file
# ships a real AF:MANAGED region (the mechanism stays dormant). Local bash/WSL
# verification is tracked as a follow-up (measure 2b Option B).
_has_region_marker() {
    grep -Eq 'AF:MANAGED:[A-Za-z0-9_.-]+:START' "$1" 2>/dev/null
}
_ends_with_nl() {
    # 0 (true) iff the file's last byte is LF.
    [[ -s "$1" ]] && [[ "$(tail -c1 "$1" | od -An -tx1 | tr -d ' \n')" == "0a" ]]
}

# awk region-strip: empties every AF:MANAGED body (keeps marker lines). Output
# byte-exact via a join model (lines joined by LF, trailing LF only when the
# input had one, passed as -v endnl). Unterminated region => body kept verbatim
# (matches the Python regex, which would not match an unclosed region).
_AWK_STRIP='
BEGIN { inr=0; started=0; out=""; nbuf=0 }
function add(s){ if (started) out=out "\n" s; else { out=s; started=1 } }
{
  line=$0
  if (inr) {
    if (line ~ endre) { add(line); inr=0; nbuf=0 }
    else { bbuf[++nbuf]=line }
  } else if (match(line, /AF:MANAGED:[A-Za-z0-9_.-]+:START/)) {
    nm=line; sub(/.*AF:MANAGED:/,"",nm); sub(/:START.*/,"",nm)
    ename=nm; gsub(/\./,"\\.",ename); endre="AF:MANAGED:" ename ":END"
    inr=1; nbuf=0; add(line)
  } else { add(line) }
}
END {
  if (inr) { for (i=1;i<=nbuf;i++) add(bbuf[i]) }
  printf "%s", out
  if (endnl) printf "\n"
}'

# awk region-merge: reconstruct the base (2nd file) with each region body
# replaced by the overlay (1st file, read via FNR==NR) same-named region body.
# Overlay bodies are committed only on a matching END (an unterminated overlay
# region contributes nothing, matching Python finditer). endnl derives from the
# base file.
_AWK_MERGE='
BEGIN { oinr=0; cur=0; cn=0; inr=0; bn=0; started=0; out="" }
function add(s){ if (started) out=out "\n" s; else { out=s; started=1 } }
FNR==NR {
  line=$0
  if (cur) {
    if (line ~ cendre) {
      ohas[cname]=1; obn[cname]=cn
      for (i=1;i<=cn;i++) obl[cname SUBSEP i]=cbl[i]
      cur=0
    } else { cbl[++cn]=line }
  } else if (match(line, /AF:MANAGED:[A-Za-z0-9_.-]+:START/)) {
    nm=line; sub(/.*AF:MANAGED:/,"",nm); sub(/:START.*/,"",nm)
    cname=nm; ename=nm; gsub(/\./,"\\.",ename); cendre="AF:MANAGED:" ename ":END"
    cur=1; cn=0
  }
  next
}
{
  line=$0
  if (inr) {
    if (line ~ endre) {
      if (name in ohas) { for (i=1;i<=obn[name];i++) add(obl[name SUBSEP i]) }
      else { for (i=1;i<=bn;i++) add(bbuf[i]) }
      add(line); inr=0
    } else { bbuf[++bn]=line }
  } else if (match(line, /AF:MANAGED:[A-Za-z0-9_.-]+:START/)) {
    nm=line; sub(/.*AF:MANAGED:/,"",nm); sub(/:START.*/,"",nm)
    name=nm; ename=nm; gsub(/\./,"\\.",ename); endre="AF:MANAGED:" ename ":END"
    inr=1; bn=0; add(line)
  } else { add(line) }
}
END {
  if (inr) { for (i=1;i<=bn;i++) add(bbuf[i]) }
  printf "%s", out
  if (endnl) printf "\n"
}'

strip_regions_to() {
    # $1=infile (canonical LF text) $2=outfile ; byte-exact region-stripped copy.
    local in="$1" out="$2" e=0
    _ends_with_nl "$in" && e=1
    awk -v endnl="$e" "$_AWK_STRIP" "$in" > "$out"
}

source_hash_resolved() {
    # Classification hash of the canonical deployed content (LF, no BOM,
    # tier-resolved) with managed-region bodies stripped (region content is
    # project-owned, not framework).
    local src="$1" tmp strip h
    tmp="$(mktemp)"
    canonical_write "$src" "$tmp"
    if _has_region_marker "$tmp"; then
        strip="$(mktemp)"
        strip_regions_to "$tmp" "$strip"
        h="$(file_hash "$strip")"
        rm -f "$strip"
    else
        h="$(file_hash "$tmp")"
    fi
    rm -f "$tmp"
    printf '%s' "$h"
}

target_classify_hash() {
    # Classification hash of a deployed target file (managed regions stripped).
    local tgt="$1" strip h
    if _has_region_marker "$tgt"; then
        strip="$(mktemp)"
        strip_regions_to "$tgt" "$strip"
        h="$(file_hash "$strip")"
        rm -f "$strip"
    else
        h="$(file_hash "$tgt")"
    fi
    printf '%s' "$h"
}

write_deployed() {
    # Write the canonical deployed bytes of $1 to $2, transplanting the existing
    # target's managed-region body onto the framework base so project-owned
    # regions survive an UPDATE. No-op merge without regions on both sides.
    local src="$1" tgt="$2" tmp e=0
    tmp="$(mktemp)"
    canonical_write "$src" "$tmp"
    if [[ -f "$tgt" ]] && _has_region_marker "$tmp" && _has_region_marker "$tgt"; then
        _ends_with_nl "$tmp" && e=1
        if awk -v endnl="$e" "$_AWK_MERGE" "$tgt" "$tmp" > "$tgt.__afmrg"; then
            mv "$tgt.__afmrg" "$tgt"
        else
            rm -f "$tgt.__afmrg"; mv "$tmp" "$tgt"; return
        fi
        rm -f "$tmp"
    else
        mv "$tmp" "$tgt"
    fi
}

is_deactivated_skill_unit() {
    # Measure #3: an active-by-default skill the project deactivated by *moving* it
    # to skills/_available/{name}/. When the framework still ships skills/{name}/ but
    # the target has skills/_available/{name}/, the deploy classifies it DEACTIVATED
    # (suppressed) instead of re-CREATE-ing it. Parity with deploy_core
    # _is_deactivated_skill_unit and deploy.ps1 Test-DeactivatedSkillUnit.
    local key="${1//\\//}" name
    case "$key" in
        skills/_available/*) return 1 ;;
        skills/*/*)
            name="${key#skills/}"; name="${name%%/*}"
            [[ -d "$TARGET_GITHUB/skills/_available/$name" ]] && return 0 || return 1 ;;
        *) return 1 ;;
    esac
}
# ── Hash-based 3-way merge ────────────────────────────────────────────────
HASH_FILE="$TARGET_GITHUB/.af-hashes"
declare -A BASELINE_HASHES
declare -A DEPLOYED_HASHES
HAS_BASELINE=false

read_hash_file() {
    if [[ -f "$HASH_FILE" ]]; then
        while IFS= read -r hline; do
            if [[ "$hline" =~ ^([^#=]+)=(.+)$ ]]; then
                local key="${BASH_REMATCH[1]}"
                local val="${BASH_REMATCH[2]}"
                key="$(echo "$key" | sed 's/[[:space:]]*$//' | tr '\\' '/')"
                val="$(echo "$val" | sed 's/^[[:space:]]*//')"
                BASELINE_HASHES["$key"]="$val"
            fi
        done < "$HASH_FILE"
        if [[ ${#BASELINE_HASHES[@]} -gt 0 ]]; then
            HAS_BASELINE=true
        fi
    fi
}

write_hash_file() {
    mkdir -p "$(dirname "$HASH_FILE")"
    {
        echo "# AF deployment baseline hashes"
        echo "# Updated: $(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')"
        echo "# Version: $AF_VERSION"
        # Sort keys for consistent output
        for key in $(echo "${!DEPLOYED_HASHES[@]}" | tr ' ' '\n' | sort); do
            echo "$key=${DEPLOYED_HASHES[$key]}"
        done
    } > "$HASH_FILE"
}

read_hash_file

# Copy baseline into deployed hashes
for k in "${!BASELINE_HASHES[@]}"; do
    DEPLOYED_HASHES["$k"]="${BASELINE_HASHES[$k]}"
done

# ── Helper: show content diff ─────────────────────────────────────────────
show_content_diff() {
    local file_a="$1" file_b="$2"
    local max_lines="${3:-15}"
    if command -v git &>/dev/null; then
        local diff_output
        diff_output="$(git diff --no-index --color=never -U2 -- "$file_a" "$file_b" 2>&1 || true)"
        local body
        body="$(echo "$diff_output" | grep -E '^[-+@]' | grep -vE '^(---|\+\+\+|diff |index )' || true)"
        if [[ -n "$body" ]]; then
            echo "$body" | head -n "$max_lines" | while IFS= read -r l; do
                echo "      $l"
            done
            local total
            total="$(echo "$body" | wc -l)"
            if [[ "$total" -gt "$max_lines" ]]; then
                echo "      ... ($((total - max_lines)) more lines)"
            fi
        fi
    elif command -v diff &>/dev/null; then
        diff -u "$file_a" "$file_b" 2>/dev/null | head -n "$max_lines" | while IFS= read -r l; do
            echo "      $l"
        done
    fi
}

# ── Helper: ephemeral backup ──────────────────────────────────────────────
backup_before_overwrite() {
    local target_file="$1" display_path="$2"
    if [[ "$DRY_RUN" == "true" ]] || [[ ! -f "$target_file" ]]; then
        return
    fi
    if [[ -z "$BACKUP_DIR" ]]; then
        local timestamp
        timestamp="$(date +%Y%m%d%H%M%S)"
        BACKUP_DIR="$TARGET_DIR/.af-backup-$timestamp"
    fi
    local backup_path="$BACKUP_DIR/$display_path"
    mkdir -p "$(dirname "$backup_path")"
    cp "$target_file" "$backup_path"
    ((BACKUP_COUNT++)) || true
}

prune_old_backups() {
    local root_dir="$1"
    local days="$2"
    local active_backup_dir="$3"

    [[ "$days" -le 0 ]] && return

    local find_days=$((days - 1))
    local stale=()
    while IFS= read -r -d '' dir; do
        if [[ -n "$active_backup_dir" ]] && [[ "$dir" == "$active_backup_dir" ]]; then
            continue
        fi
        stale+=("$dir")
    done < <(find "$root_dir" -maxdepth 1 -mindepth 1 -type d -name '.af-backup-*' -mtime +"$find_days" -print0 2>/dev/null)

    [[ ${#stale[@]} -eq 0 ]] && return

    echo ""
    echo "=== Backup Prune ==="
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY RUN] Would remove ${#stale[@]} stale backup folder(s) older than $days day(s)."
        printf '%s\n' "${stale[@]}" | sort | while IFS= read -r d; do
            echo "  WOULD   $d"
        done
        return
    fi

    printf '%s\n' "${stale[@]}" | sort | while IFS= read -r d; do
        rm -rf "$d"
        echo "  PRUNE   $d"
    done
    echo "  Pruned ${#stale[@]} stale backup folder(s) older than $days day(s)."
}

cleanup_conflict_backups() {
    local root_dir="$1"
    local backups=()
    while IFS= read -r -d '' dir; do
        backups+=("$dir")
    done < <(find "$root_dir" -maxdepth 1 -mindepth 1 -type d -name '.af-backup-*' -print0 2>/dev/null)

    [[ ${#backups[@]} -eq 0 ]] && return

    echo ""
    echo "=== Conflict Backup Cleanup ==="
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY RUN] Would remove ${#backups[@]} conflict backup folder(s)."
        printf '%s\n' "${backups[@]}" | sort | while IFS= read -r d; do
            echo "  WOULD   $d"
        done
        return
    fi

    printf '%s\n' "${backups[@]}" | sort | while IFS= read -r d; do
        rm -rf "$d"
        echo "  CLEAN   $d"
    done
    echo "  Removed ${#backups[@]} conflict backup folder(s)."
}

test_notebook_git_filter_config() {
    if [[ ! -f "$TARGET_AF_ENV" ]]; then
        return 0
    fi

    if ! grep -qE '^NOTEBOOKS_ENABLED=true$' "$TARGET_AF_ENV"; then
        return 0
    fi

    local ga="$TARGET_DIR/.gitattributes"
    if [[ ! -f "$ga" ]]; then
        return 2
    fi

    if ! grep -q 'filter=nbstripout' "$ga"; then
        return 2
    fi

    return 0
}

# ── Collect all source files ───────────────────────────────────────────────
# Python bytecode caches regenerate whenever a hook/script test runs; they must
# never enter the deploy payload. Emit only deployable files (null-delimited).
find_deployable_files() {
    find "$1" -type f -not -path '*/__pycache__/*' -not -name '*.pyc' -not -name '*.pyo' -print0
}
get_af_source_files() {
    # Outputs relative paths under .github/ (one per line)
    for dir in "${MANIFEST_DIRS[@]}"; do
        local src_dir="$SOURCE_GITHUB/$dir"
        [[ ! -d "$src_dir" ]] && continue
        find_deployable_files "$src_dir" | while IFS= read -r -d '' file; do
            echo "${file#"$SOURCE_GITHUB"/}"
        done
    done
    for f in "${MANIFEST_ROOT_FILES[@]}"; do
        [[ -f "$SOURCE_GITHUB/$f" ]] && echo "$f"
    done
}

run_integrity_preflight() {
    local mode="$1"
    local required="$2"

    echo "=== AF Preflight ($mode) ==="

    local checks=()
    checks+=("Hook integration tests|powershell -NoProfile -ExecutionPolicy Bypass -File \"$AF_ROOT/.github/scripts/test-hooks.ps1\"")
    checks+=("Skills validation|$(command -v python3 >/dev/null 2>&1 && echo python3 || echo python) \"$AF_ROOT/.github/scripts/validate-skills.py\"")
    checks+=("Tool audit|powershell -NoProfile -ExecutionPolicy Bypass -File \"$AF_ROOT/.github/scripts/audit-tools.ps1\"")
    checks+=("Notebook git filter alignment (NOTEBOOKS_ENABLED=true)|test_notebook_git_filter_config")

    if [[ "$mode" == "full" ]]; then
        checks+=("Worktree integration tests|powershell -NoProfile -ExecutionPolicy Bypass -File \"$AF_ROOT/.github/scripts/test-worktree-scripts.ps1\"")
    fi

    local failed=0
    local total=0
    local failures=()

    for entry in "${checks[@]}"; do
        IFS='|' read -r name cmd <<< "$entry"
        ((total++)) || true
        echo "  RUN     $name"
        if eval "$cmd" >/dev/null 2>&1; then
            echo "  PASS    $name"
        else
            local code=$?
            echo "  FAIL    $name (exit $code)"
            ((failed++)) || true
            failures+=("$name [exit $code]")
        fi
    done

    if [[ "$failed" -eq 0 ]]; then
        echo "  RESULT  PASS ($total/$total)"
        echo ""
        return 0
    fi

    echo "  RESULT  FAIL ($((total-failed))/$total)"
    for f in "${failures[@]}"; do
        echo "          - $f"
    done
    echo ""

    if [[ "$required" == "true" ]]; then
        echo "Preflight required and failed. Deployment blocked."
        exit 1
    fi

    echo "Preflight failed, but deployment will continue (optional mode)."
    echo ""
    return 0
}

# ── UpdateHashes mode ─────────────────────────────────────────────────────
if [[ "$UPDATE_HASHES" == "true" ]]; then
    echo ""
    echo "=== Update AF Baseline Hashes ==="
    # Clear deployed hashes and rebuild from source
    DEPLOYED_HASHES=()
    while IFS= read -r rel; do
        src="$SOURCE_GITHUB/$rel"
        DEPLOYED_HASHES["$rel"]="$(source_hash_resolved "$src")"
    done < <(get_af_source_files)
    for f in "${MANIFEST_VSCODE_FILES[@]}"; do
        src="$SOURCE_VSCODE/$f"
        if [[ -f "$src" ]]; then
            DEPLOYED_HASHES["vscode/$f"]="$(source_hash_resolved "$src")"
        fi
    done
    if [[ "$DRY_RUN" != "true" ]]; then
        write_hash_file
        echo "  Wrote .af-hashes with ${#DEPLOYED_HASHES[@]} entries (v$AF_VERSION)"
    else
        echo "  [DRY RUN] Would write .af-hashes with ${#DEPLOYED_HASHES[@]} entries"
    fi
    cleanup_conflict_backups "$TARGET_DIR"
    echo ""
    exit 0
fi

# ── Deploy a single file ──────────────────────────────────────────────────
deploy_file() {
    local src="$1" tgt="$2" display="$3" hash_key="${4:-}"
    if [[ -z "$hash_key" ]]; then
        hash_key="${display#.github/}"
    fi
    local is_custom=false
    if is_customizable "$hash_key"; then
        is_custom=true
    fi
    local source_hash
    source_hash="$(source_hash_resolved "$src")"

    # ── New file: always deploy ──
    if [[ ! -f "$tgt" ]]; then
        if is_deactivated_skill_unit "$hash_key"; then
            echo "  DEACTIVATED $display  (skill moved to _available/)"
            ((STAT_DEACTIVATED++)) || true
            return
        fi
        echo "  CREATE  $display"
        ((STAT_CREATED++)) || true
        DEPLOYED_HASHES["$hash_key"]="$source_hash"
    else
        local target_hash
        target_hash="$(target_classify_hash "$tgt")"

        # ── Identical: nothing to do ──
        if [[ "$source_hash" == "$target_hash" ]]; then
            DEPLOYED_HASHES["$hash_key"]="$source_hash"
            ((STAT_UNCHANGED++)) || true
            return
        fi

        # ── 3-way merge detection ──
        local baseline_hash="${BASELINE_HASHES[$hash_key]:-}"

        if [[ -n "$baseline_hash" ]]; then
            local af_changed=false proj_changed=false
            [[ "$source_hash" != "$baseline_hash" ]] && af_changed=true
            [[ "$target_hash" != "$baseline_hash" ]] && proj_changed=true

            # Customizable files: never auto-overwrite (unless --force)
            if $is_custom && [[ "$FORCE" != "true" ]]; then
                if $af_changed && $proj_changed; then
                    echo "  CONFLICT $display  (both AF and project changed)"
                    show_content_diff "$src" "$tgt"
                    ((STAT_CONFLICT++)) || true
                elif $af_changed; then
                    echo "  PROTECT $display  (AF has changes -- review manually)"
                    ((STAT_PROTECTED++)) || true
                else
                    echo "  PRESERVE $display  (project customization)"
                    ((STAT_PRESERVED++)) || true
                fi
                return
            fi

            # Non-customizable (or --force) 3-way merge
            if $af_changed && ! $proj_changed; then
                echo "  UPDATE  $display"
                ((STAT_UPDATED++)) || true
                DEPLOYED_HASHES["$hash_key"]="$source_hash"
            elif ! $af_changed && $proj_changed; then
                echo "  PRESERVE $display  (project customization)"
                ((STAT_PRESERVED++)) || true
                return
            else
                echo "  CONFLICT $display  (both AF and project changed)"
                show_content_diff "$src" "$tgt"
                ((STAT_CONFLICT++)) || true
                return
            fi
        elif $HAS_BASELINE; then
            # Hash file exists but file not tracked — new in AF
            if $is_custom && [[ "$FORCE" != "true" ]]; then
                echo "  PROTECT $display  (new in AF, customizable -- review manually)"
                ((STAT_PROTECTED++)) || true
                return
            fi
            echo "  UPDATE  $display"
            ((STAT_UPDATED++)) || true
            DEPLOYED_HASHES["$hash_key"]="$source_hash"
        else
            # No hash file — bootstrap — conservative
            if $is_custom && [[ "$FORCE" != "true" ]]; then
                echo "  PROTECT $display  (customizable -- use --force to overwrite)"
                ((STAT_PROTECTED++)) || true
                return
            fi
            echo "  CONFLICT $display  (no baseline -- run --update-hashes after resolving)"
            show_content_diff "$src" "$tgt"
            ((STAT_CONFLICT++)) || true
            return
        fi
    fi

    # Perform the copy (with backup for existing files)
    if [[ "$DRY_RUN" != "true" ]]; then
        backup_before_overwrite "$tgt" "$display"
        mkdir -p "$(dirname "$tgt")"
        write_deployed "$src" "$tgt"
    fi
}

# ══════════════════════════════════════════════════════════════════════════
# DIFF MODE
# ══════════════════════════════════════════════════════════════════════════
if [[ "$DIFF_MODE" == "true" ]]; then
    echo ""
    echo "=== AF Deployment Diff ==="
    echo "  AF source version : $AF_VERSION"
    echo "  Deployed version  : ${DEPLOYED_INFO:-(not deployed)}"
    echo ""

    DIFF_COUNT=0

    # Source -> project: files in AF that are missing or differ in project
    while IFS= read -r rel; do
        src="$SOURCE_GITHUB/$rel"
        tgt="$TARGET_GITHUB/$rel"
        if [[ ! -f "$tgt" ]]; then
            if is_deactivated_skill_unit "$rel"; then
                printf "  -- skip      %-50s  DEACTIVATED (moved to _available/)\n" ".github/$rel"
            else
                printf "  -> project   %-50s  New in AF\n" ".github/$rel"
                ((DIFF_COUNT++)) || true
            fi
        else
            sh="$(source_hash_resolved "$src")"
            th="$(target_classify_hash "$tgt")"
            if [[ "$sh" != "$th" ]]; then
                bh="${BASELINE_HASHES[$rel]:-}"
                if [[ -n "$bh" ]]; then
                    if [[ "$sh" != "$bh" ]] && [[ "$th" == "$bh" ]]; then
                        printf "  -> UPDATE    %-50s  AF changed (safe to deploy)\n" ".github/$rel"
                    elif [[ "$sh" == "$bh" ]] && [[ "$th" != "$bh" ]]; then
                        printf "  <- CUSTOM    %-50s  Project customized (preserved)\n" ".github/$rel"
                    else
                        printf "  !! CONFLICT  %-50s  Both AF and project changed\n" ".github/$rel"
                    fi
                else
                    printf "  <->          %-50s  Modified (no baseline)\n" ".github/$rel"
                fi
                ((DIFF_COUNT++)) || true
            fi
        fi
    done < <(get_af_source_files)

    # Project -> AF: files added in project but not in AF source
    for dir in "${MANIFEST_DIRS[@]}"; do
        tgt_dir="$TARGET_GITHUB/$dir"
        [[ ! -d "$tgt_dir" ]] && continue
        while IFS= read -r -d '' file; do
            rel="${file#"$TARGET_GITHUB"/}"
            src="$SOURCE_GITHUB/$rel"
            if [[ ! -f "$src" ]]; then
                printf "  <- project   %-50s  Added in project\n" ".github/$rel"
                ((DIFF_COUNT++)) || true
            fi
        done < <(find_deployable_files "$tgt_dir")
    done

    # Check vscode files from manifest
    for f in "${MANIFEST_VSCODE_FILES[@]}"; do
        src="$SOURCE_VSCODE/$f"
        tgt="$TARGET_VSCODE/$f"
        if [[ -f "$src" ]] && [[ ! -f "$tgt" ]]; then
            printf "  -> project   %-50s  New in AF\n" ".vscode/$f"
            ((DIFF_COUNT++)) || true
        elif [[ -f "$src" ]] && [[ -f "$tgt" ]]; then
            sh="$(source_hash_resolved "$src")"
            th="$(target_classify_hash "$tgt")"
            if [[ "$sh" != "$th" ]]; then
                bh="${BASELINE_HASHES[vscode/$f]:-}"
                if [[ -n "$bh" ]]; then
                    if [[ "$sh" != "$bh" ]] && [[ "$th" == "$bh" ]]; then
                        printf "  -> UPDATE    %-50s  AF changed (safe to deploy)\n" ".vscode/$f"
                    elif [[ "$sh" == "$bh" ]] && [[ "$th" != "$bh" ]]; then
                        printf "  <- CUSTOM    %-50s  Project customized (preserved)\n" ".vscode/$f"
                    else
                        printf "  !! CONFLICT  %-50s  Both AF and project changed\n" ".vscode/$f"
                    fi
                else
                    printf "  <->          %-50s  Modified (no baseline)\n" ".vscode/$f"
                fi
                ((DIFF_COUNT++)) || true
            fi
        fi
    done

    echo ""
    if [[ "$DIFF_COUNT" -eq 0 ]]; then
        echo "  No differences. Deployment is in sync."
    else
        echo "  $DIFF_COUNT difference(s) found."
        echo ""
        echo "  -> project  : New in AF, not yet deployed"
        echo "  <- project  : Added in project, not in AF source"
        echo "  -> UPDATE   : AF changed, project unchanged (safe to deploy)"
        echo "  <- CUSTOM   : Project customized, AF unchanged (preserved)"
        echo "  !! CONFLICT : Both AF and project changed (needs manual merge)"
        echo "  <->         : Modified (no baseline -- run --update-hashes)"
    fi
    echo ""
    exit 0
fi

# ══════════════════════════════════════════════════════════════════════════
# DEPLOY MODE
# ══════════════════════════════════════════════════════════════════════════
if [[ "$PREFLIGHT" == "true" || "$REQUIRE_PREFLIGHT" == "true" ]]; then
    run_integrity_preflight "$PREFLIGHT_MODE" "$REQUIRE_PREFLIGHT"
fi

BACKUP_PRUNE_DAYS="$(resolve_backup_prune_days)"
if [[ ! "$BACKUP_PRUNE_DAYS" =~ ^[0-9]+$ ]]; then
    echo "Error: backup prune days must be a non-negative integer (CLI or af-env.conf BACKUP_PRUNE_DAYS)" >&2
    exit 1
fi
if [[ "$BACKUP_PRUNE_DAYS" -gt 3650 ]]; then
    echo "Error: backup prune days must be <= 3650" >&2
    exit 1
fi

echo ""
echo "=== AF Deployment ==="
echo "  Source  : $AF_ROOT"
echo "  Target  : $TARGET_DIR"
echo "  Version : $AF_VERSION"
if [[ "$BACKUP_PRUNE_DAYS" -gt 0 ]]; then
    echo "  Backup prune: enabled (older than $BACKUP_PRUNE_DAYS day(s))"
else
    echo "  Backup prune: disabled"
fi
if target_is_git_repo "$TARGET_DIR"; then
    CURRENT_BRANCH="$(get_current_git_branch "$TARGET_DIR")"
    if [[ "$CURRENT_BRANCH" == agent/* ]]; then
        echo "  WARNING: Target repo is on '$CURRENT_BRANCH'. Prefer running framework rollouts on dev/main."
    fi
else
    CURRENT_BRANCH=""
    echo "  Note: Target is not a git repository -- branch checks skipped."
fi
if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [DRY RUN — no changes will be made]"
fi
echo ""

# Deploy .github/ directories
echo "  .github/ directories:"
for dir in "${MANIFEST_DIRS[@]}"; do
    src_dir="$SOURCE_GITHUB/$dir"
    [[ ! -d "$src_dir" ]] && continue
    while IFS= read -r -d '' file; do
        rel="${file#"$SOURCE_GITHUB"/}"
        deploy_file "$file" "$TARGET_GITHUB/$rel" ".github/$rel" "$rel"
    done < <(find_deployable_files "$src_dir" | sort -z)
done

echo ""
echo "  .github/ root files:"
for f in "${MANIFEST_ROOT_FILES[@]}"; do
    src="$SOURCE_GITHUB/$f"
    [[ ! -f "$src" ]] && continue
    deploy_file "$src" "$TARGET_GITHUB/$f" ".github/$f" "$f"
done

# Deploy vscode files from manifest
if [[ ${#MANIFEST_VSCODE_FILES[@]} -gt 0 ]]; then
    echo ""
    echo "  .vscode/:"
    for f in "${MANIFEST_VSCODE_FILES[@]}"; do
        src="$SOURCE_VSCODE/$f"
        [[ ! -f "$src" ]] && continue
        deploy_file "$src" "$TARGET_VSCODE/$f" ".vscode/$f" "vscode/$f"
    done
fi

# Write .af-hashes
if [[ "$DRY_RUN" != "true" ]]; then
    write_hash_file
fi
echo ""
echo "  WRITE   .github/.af-hashes"

# Write .af-version
if [[ "$DRY_RUN" != "true" ]]; then
    mkdir -p "$TARGET_GITHUB"
    cat > "$DEPLOYED_VERSION_FILE" <<EOF
version: $AF_VERSION
deployed: $(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')
source: $AF_ROOT
EOF
fi
echo "  WRITE   .github/.af-version"

# ── Project context budgets ────────────────────────────────────────────────
# The context budget gate splits its ceilings: AF's own instruction files are
# measured against limits calibrated in the framework repository, and the
# project's own files against limits calibrated here. The second pair cannot
# ship as a constant -- a number that fits this project fails the next one, and
# a number generous enough for every project measures nothing (issue #107).
# So a fresh install seeds them from what the target actually has.
#
# Only on a fresh install. On an update af-env.conf is customizable and
# protected, and whatever is in it is a baseline someone chose; overwriting it
# would erase the drift the gate exists to detect.
if [[ "$AF_ENV_WAS_ABSENT" == "1" && "$DRY_RUN" != "true" ]]; then
    budget_script="$TARGET_GITHUB/scripts/check-context-budget.py"
    py_cmd=""
    for candidate in python3 python; do
        if command -v "$candidate" >/dev/null 2>&1; then py_cmd="$candidate"; break; fi
    done
    if [[ ! -f "$budget_script" ]]; then
        echo "  SKIP    project context budgets -- checker not deployed"
    elif [[ -z "$py_cmd" ]]; then
        echo ""
        echo "  WARN    project context budgets not seeded -- no Python found."
        echo "          af-env.conf carries the framework's own numbers, which do not"
        echo "          describe this project. Run once, then commit af-env.conf:"
        echo "            python .github/scripts/check-context-budget.py --seed-project-budget --force"
    elif "$py_cmd" "$budget_script" --github-dir "$TARGET_GITHUB" --seed-project-budget --force >/dev/null; then
        echo "  SEED    .github/af-env.conf -- project context budgets from this repository"
    else
        echo "  WARN    project context budget seeding failed -- af-env.conf keeps the framework's numbers"
    fi
fi

# Summary
echo ""
echo "=== Summary ==="
echo "  Created:   $STAT_CREATED"
echo "  Updated:   $STAT_UPDATED"
echo "  Unchanged: $STAT_UNCHANGED"
if [[ "$STAT_PROTECTED" -gt 0 ]]; then
    echo "  Protected: $STAT_PROTECTED -- review these manually"
fi
if [[ "$STAT_PRESERVED" -gt 0 ]]; then
    echo "  Preserved: $STAT_PRESERVED -- project customizations kept"
fi
if [[ "$STAT_DEACTIVATED" -gt 0 ]]; then
    echo "  Deactivated: $STAT_DEACTIVATED -- skills moved to _available/, not deployed"
fi
if [[ "$STAT_CONFLICT" -gt 0 ]]; then
    echo "  Conflict:  $STAT_CONFLICT -- both sides changed, use agent to merge"
    echo ""
    echo "  To resolve conflicts: ask the agent to merge, then run --update-hashes (the MCP af_resolve_conflicts prompt automates this)."
fi
if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    echo "  [DRY RUN — no files were changed. Remove --dry-run to apply.]"
fi

# ── Curated skills consistency ─────────────────────────────────────────────
# Curated state lives in three records (curated-assignments.json, the agent
# regions, .af-skills-curated/INDEX.md) and nothing used to compare them, so a
# lost assignment was silent (#257). Report the actual disagreement; say
# nothing when they agree. Advisory only -- never fails the deploy.
curated_json="$TARGET_GITHUB/skills/curated-assignments.json"
if [[ -f "$curated_json" ]]; then
    curation_probe="$SOURCE_GITHUB/scripts/check-curation-consistency.py"
    python_bin=""
    for candidate in python3 python; do
        if command -v "$candidate" >/dev/null 2>&1; then
            python_bin="$candidate"
            break
        fi
    done

    if [[ -f "$curation_probe" && -n "$python_bin" ]]; then
        curation_out="$("$python_bin" "$curation_probe" --project-dir "$TARGET_DIR" --brief 2>&1 || true)"
        if [[ -n "$curation_out" ]]; then
            echo ""
            echo "$curation_out"
        fi
    else
        # No Python: fall back to the reminder, minus the claim that a deploy
        # resets assignments -- managed regions made that false.
        echo ""
        echo "  Curated skills detected; consistency was not checked (no Python interpreter)."
        echo "  -> Run /af-curate-skills --reapply if agent skill sections look wrong."
    fi
fi

# ── Cost tracking source ───────────────────────────────────────────────────
# A workflow log records `cost: available: false` when VS Code's agent debug
# log is off, and that file is not one anybody opens unprompted. A deploy is
# the one moment an existing consumer is already reading framework output, and
# it is the only channel that reaches installs predating the setting -- the
# .vscode/settings.json that would carry the key is PRESERVE'd on update.
# Advisory only: never fatal, never gating (issue #228).
cost_probe="$SOURCE_GITHUB/scripts/check-cost-source.sh"
if [[ -f "$cost_probe" ]]; then
    cost_output=$(bash "$cost_probe" --brief 2>/dev/null)
    if [[ -n "$cost_output" ]]; then
        echo ""
        echo "$cost_output"
    fi
fi

# Prune stale backups from previous deploy runs
prune_old_backups "$TARGET_DIR" "$BACKUP_PRUNE_DAYS" "$BACKUP_DIR"

if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    echo "  DRYRUN_JSON {\"mode\":\"dry-run\",\"created\":$STAT_CREATED,\"updated\":$STAT_UPDATED,\"unchanged\":$STAT_UNCHANGED,\"protected\":$STAT_PROTECTED,\"preserved\":$STAT_PRESERVED,\"deactivated\":$STAT_DEACTIVATED,\"conflict\":$STAT_CONFLICT,\"backup_prune_days\":$BACKUP_PRUNE_DAYS}"
fi

# Backup cleanup
if [[ -n "$BACKUP_DIR" ]] && [[ -d "$BACKUP_DIR" ]]; then
    if [[ "$STAT_CONFLICT" -eq 0 ]]; then
        rm -rf "$BACKUP_DIR"
        echo ""
        echo "  Backup cleaned up (no conflicts)."
    else
        echo ""
        echo "  Backup: $BACKUP_DIR  ($BACKUP_COUNT files)"
        echo "  Delete manually after resolving conflicts."
    fi
fi

echo ""
exit 0
