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

Options:
  -t, --target DIR       Project root (default: parent of AF directory)
  -n, --dry-run          Show what would be copied without making changes
  -d, --diff             Compare AF source against deployed copy
  -f, --force            Overwrite customizable files
  -u, --update-hashes    Write baseline hashes from current AF source
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

while [[ $# -gt 0 ]]; do
    case "$1" in
        -t|--target)        TARGET_DIR="$2"; shift 2 ;;
        -n|--dry-run)       DRY_RUN=true; shift ;;
        -d|--diff)          DIFF_MODE=true; shift ;;
        -f|--force)         FORCE=true; shift ;;
        -u|--update-hashes) UPDATE_HASHES=true; shift ;;
        -h|--help)          usage ;;
        *)                  echo "Unknown option: $1" >&2; usage ;;
    esac
done

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
BACKUP_DIR=""
BACKUP_COUNT=0

# ── Helper: is file customizable ──────────────────────────────────────────
is_customizable() {
    [[ -n "${CUSTOMIZABLE_MAP[$1]+x}" ]]
}

# ── Helper: file hash ─────────────────────────────────────────────────────
file_hash() {
    if command -v sha256sum &>/dev/null; then
        sha256sum "$1" | cut -d' ' -f1
    elif command -v shasum &>/dev/null; then
        shasum -a 256 "$1" | cut -d' ' -f1
    else
        md5sum "$1" | cut -d' ' -f1
    fi
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
                key="$(echo "$key" | sed 's/[[:space:]]*$//')"
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

# ── Collect all source files ───────────────────────────────────────────────
get_af_source_files() {
    # Outputs relative paths under .github/ (one per line)
    for dir in "${MANIFEST_DIRS[@]}"; do
        local src_dir="$SOURCE_GITHUB/$dir"
        [[ ! -d "$src_dir" ]] && continue
        find "$src_dir" -type f -print0 | while IFS= read -r -d '' file; do
            echo "${file#"$SOURCE_GITHUB"/}"
        done
    done
    for f in "${MANIFEST_ROOT_FILES[@]}"; do
        [[ -f "$SOURCE_GITHUB/$f" ]] && echo "$f"
    done
}

# ── UpdateHashes mode ─────────────────────────────────────────────────────
if [[ "$UPDATE_HASHES" == "true" ]]; then
    echo ""
    echo "=== Update AF Baseline Hashes ==="
    # Clear deployed hashes and rebuild from source
    DEPLOYED_HASHES=()
    while IFS= read -r rel; do
        src="$SOURCE_GITHUB/$rel"
        DEPLOYED_HASHES["$rel"]="$(file_hash "$src")"
    done < <(get_af_source_files)
    for f in "${MANIFEST_VSCODE_FILES[@]}"; do
        src="$SOURCE_VSCODE/$f"
        if [[ -f "$src" ]]; then
            DEPLOYED_HASHES["vscode/$f"]="$(file_hash "$src")"
        fi
    done
    if [[ "$DRY_RUN" != "true" ]]; then
        write_hash_file
        echo "  Wrote .af-hashes with ${#DEPLOYED_HASHES[@]} entries (v$AF_VERSION)"
    else
        echo "  [DRY RUN] Would write .af-hashes with ${#DEPLOYED_HASHES[@]} entries"
    fi
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
    source_hash="$(file_hash "$src")"

    # ── New file: always deploy ──
    if [[ ! -f "$tgt" ]]; then
        echo "  CREATE  $display"
        ((STAT_CREATED++)) || true
        DEPLOYED_HASHES["$hash_key"]="$source_hash"
    else
        local target_hash
        target_hash="$(file_hash "$tgt")"

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
        cp "$src" "$tgt"
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
            printf "  -> project   %-50s  New in AF\n" ".github/$rel"
            ((DIFF_COUNT++)) || true
        else
            sh="$(file_hash "$src")"
            th="$(file_hash "$tgt")"
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
        done < <(find "$tgt_dir" -type f -print0)
    done

    # Check vscode files from manifest
    for f in "${MANIFEST_VSCODE_FILES[@]}"; do
        src="$SOURCE_VSCODE/$f"
        tgt="$TARGET_VSCODE/$f"
        if [[ -f "$src" ]] && [[ ! -f "$tgt" ]]; then
            printf "  -> project   %-50s  New in AF\n" ".vscode/$f"
            ((DIFF_COUNT++)) || true
        elif [[ -f "$src" ]] && [[ -f "$tgt" ]]; then
            sh="$(file_hash "$src")"
            th="$(file_hash "$tgt")"
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
echo ""
echo "=== AF Deployment ==="
echo "  Source  : $AF_ROOT"
echo "  Target  : $TARGET_DIR"
echo "  Version : $AF_VERSION"
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
    done < <(find "$src_dir" -type f -print0 | sort -z)
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
if [[ "$STAT_CONFLICT" -gt 0 ]]; then
    echo "  Conflict:  $STAT_CONFLICT -- both sides changed, use agent to merge"
    echo ""
    echo "  To resolve conflicts: ask the agent to merge, then run --update-hashes"
fi
if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    echo "  [DRY RUN — no files were changed. Remove --dry-run to apply.]"
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
