#!/usr/bin/env bash
# PreToolUse hook: three-tier terminal command classifier (allow / ask / deny),
# plus two task-launch classifiers (creation and execution).
#
# Tiers (runInTerminal shape): deny (hard-block), allow (auto-approve safe),
# ask (confirm durable change), {} (defer to user settings -- fail-safe
# default).
#
# A task is a second way to execute a command line, so it is classified twice,
# at both points where the danger can enter (issue #74):
#
#   CREATION -- create_and_run_task (the agent authors the task). Allowlist:
#     task.command must resolve (after path normalisation) inside a directory
#     listed in AF_TASK_SCRIPT_DIRS -- a bare binary (git, ruff, pytest, ...)
#     never can, since it has no path segment to match, so the hard-deny tier
#     is covered as a consequence. Any unrecognised task shape denies.
#
#   EXECUTION -- run_task (a task already in .vscode/tasks.json runs). The
#     payload carries only {id, workspaceFolder}: a name, not a command. The
#     task is resolved out of tasks.json and its reconstructed command line is
#     put through the SAME three tiers as a terminal command -- blocklist, not
#     the creation allowlist, because tasks.json is human-authored and
#     legitimately calls bare binaries. Checked separately from creation
#     because a task that was acceptable when written may not be acceptable
#     now: policy, protected branches and categories all move underneath it.
#     Anything unresolvable answers ask, never silence (issue #68).

# Root, config and interpreter come from this script's location, never from
# the cwd the agent happens to run in (issue #54). AF_PYTHON is probed, not
# merely resolved: on Windows `command -v python3` finds the App Execution
# Alias, which is non-empty but runs nothing -- every python call would then
# fail silently and the hook would emit no opinion for any command.
. "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
PYTHON="$AF_PYTHON"

raw=$(cat)

if [ -z "$PYTHON" ]; then
    echo '{}'
    exit 0
fi

tool_name=$(echo "$raw" | "$PYTHON" -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

# create_and_run_task and run_task are the names VS Code actually sends; the
# camelCase spellings never occur in a captured payload and are kept only so a
# rename upstream degrades to a stale alias rather than to an inert gate.
case "$tool_name" in
    *terminal*|*Terminal*) ;;
    create_and_run_task|createAndRunTask) ;;
    run_task|runTask) ;;
    *) echo '{}'; exit 0 ;;
esac

if [ "$tool_name" = "createAndRunTask" ] || [ "$tool_name" = "create_and_run_task" ]; then
    # ------------------------------------------------------------------
    # createAndRunTask allowlist -- mirrors block-dangerous.ps1. A task's
    # `command` must resolve, after path normalisation, inside one of the
    # AF_TASK_SCRIPT_DIRS directories -- a bare binary (git, ruff, pytest,
    # databricks, ...) never can, since it has no path segment to match.
    # An interpreter (powershell/cmd/bash/python/...) is checked by its
    # PAYLOAD instead (-File/-c/a positional script path), because that is
    # what actually runs and the interpreter binary itself is never inside
    # the repo. Everything unrecognised fails closed. Path normalisation
    # and the JSON walk are delegated to Python (already a hard dependency
    # of this hook) rather than re-implemented in shell.
    # ------------------------------------------------------------------
    emit_task() {
        # $1 = decision, $2 = reason
        # The deny reasons quote the offending task command back at the reader,
        # and a task command is a path -- on Windows a backslash path. Raw
        # interpolation would emit \s, an invalid JSON escape, and an
        # unparsable verdict reads exactly like no verdict at all.
        local reason
        reason=$(printf '%s' "$2" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\r' | tr '\n' ' ')
        printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' "$1" "$reason"
        exit 0
    }

    for marker in '${input:' '${command:' '${config:'; do
        if printf '%s' "$raw" | grep -qF "$marker"; then
            emit_task deny "Policy hard-deny: task payload contains a $marker...} variable. Its value is produced elsewhere -- a prompt an agent cannot answer, a VS Code command that executes to yield it, or a setting -- so the payload cannot be classified. Pass a literal argument instead. Point the task command at a reviewed script under AF_TASK_SCRIPT_DIRS (default .github/scripts), or run the command yourself in the terminal."
        fi
    done

    task_repo="$AF_CODE_ROOT"
    task_dirs_raw=$(af_conf_get AF_TASK_SCRIPT_DIRS '')
    [ -z "$task_dirs_raw" ] && task_dirs_raw=".github/scripts"

    decision=$(printf '%s' "$raw" | "$PYTHON" -c '
import sys, json, os

raw = sys.stdin.read()
repo = sys.argv[1] if len(sys.argv) > 1 else ""
dirs_raw = sys.argv[2] if len(sys.argv) > 2 else ".github/scripts"

sanctioned = (
    "Point the task command at a reviewed script under AF_TASK_SCRIPT_DIRS "
    "(default .github/scripts), e.g. .github/scripts/run-tests.ps1, or run "
    "the command yourself in the terminal."
)

def resolve(p):
    if not repo or not p:
        return None
    p = os.path.expandvars(p)
    p = p.replace("${workspaceFolder}", repo).replace("${workspaceRoot}", repo)
    # Substitution and env expansion both yield absolute paths, which must not
    # be joined onto the repo root again.
    if os.path.isabs(p):
        return os.path.normpath(p)
    return os.path.normpath(os.path.join(repo, p))

allowed = []
for d in dirs_raw.split(","):
    d = d.strip()
    if not d:
        continue
    r = resolve(d)
    if r:
        allowed.append(r + os.sep)

def in_allowlist(p):
    full = resolve(p)
    if not full:
        return False
    return any(full.lower().startswith(a.lower()) for a in allowed)

try:
    data = json.loads(raw)
except Exception:
    print("DENY|Policy hard-deny: unrecognised task payload shape (invalid JSON); fail-closed. " + sanctioned)
    sys.exit(0)

task = data.get("tool_input", {}).get("task")
if not isinstance(task, dict):
    print("DENY|Policy hard-deny: unrecognised task payload shape (no task object); fail-closed. " + sanctioned)
    sys.exit(0)

run_opts = task.get("runOptions")
if isinstance(run_opts, dict) and str(run_opts.get("runOn", "")) == "folderOpen":
    print("DENY|Policy hard-deny: runOptions.runOn folderOpen registers a task that runs automatically the next time the folder is opened, outside any hook view. " + sanctioned)
    sys.exit(0)

interpreters = {"powershell", "pwsh", "cmd", "bash", "sh", "zsh", "python", "python3", "node", "perl", "ruby", "wscript", "cscript"}

def deny_reason(command, args):
    if not command:
        return "Policy hard-deny: unrecognised task payload shape (no usable command found); fail-closed. " + sanctioned
    # type: shell hands command to the shell verbatim, so it may be a whole
    # command line. Metacharacters survive path normalisation, which would let
    # anything ride along behind an allowlisted script name.
    for ch in [";", "&", "|", "\n", "\r", "`"]:
        if ch in command:
            return "Policy hard-deny: task command " + command + " contains a shell metacharacter, so it is a command line rather than a path to a reviewed script. " + sanctioned
    if "$(" in command:
        return "Policy hard-deny: task command " + command + " contains a command substitution. " + sanctioned
    if not isinstance(args, list):
        args = []
    args = [str(a) for a in args]
    base = os.path.splitext(os.path.basename(command))[0].lower()

    if base in interpreters:
        inline = False
        file_target = None
        saw_file_flag = False
        for i, a in enumerate(args):
            if a.lower() in ("-command", "-c", "/c", "-encodedcommand"):
                inline = True
                break
            if a.lower() == "-file":
                saw_file_flag = True
                if i + 1 < len(args):
                    file_target = args[i + 1]
                break
        if inline:
            return "Policy hard-deny: interpreter " + command + " invoked with an inline command payload (-Command/-c/-EncodedCommand) that is not visible to the task classifier. " + sanctioned
        if not saw_file_flag:
            for a in args:
                if a and not a.startswith("-"):
                    file_target = a
                    break
        if not file_target or not in_allowlist(file_target):
            return "Policy hard-deny: interpreter " + command + " payload " + str(file_target) + " does not resolve inside an AF_TASK_SCRIPT_DIRS directory (unrecognised or external script). " + sanctioned
        return None

    if not in_allowlist(command):
        return "Policy hard-deny: task command " + command + " does not resolve inside an AF_TASK_SCRIPT_DIRS directory. " + sanctioned
    return None

# An OS-specific scope overrides the task scope, so every variant present must
# clear the bar -- checking only command classifies a decoy.
scopes = [("task", task)]
for osname in ("windows", "linux", "osx"):
    variant = task.get(osname)
    if isinstance(variant, dict):
        scopes.append((osname, variant))

for name, scope in scopes:
    opts = scope.get("options")
    if isinstance(opts, dict) and opts.get("shell"):
        print("DENY|Policy hard-deny: the " + name + " scope overrides options.shell, which moves the executed payload into the shell own arguments where the task classifier cannot see it. " + sanctioned)
        sys.exit(0)
    cmd = scope.get("command") or task.get("command", "")
    cmd = str(cmd) if cmd else ""
    scope_args = scope.get("args") if scope.get("args") is not None else task.get("args", [])
    reason = deny_reason(cmd, scope_args)
    if reason:
        if name != "task":
            reason = "[" + name + " override] " + reason
        print("DENY|" + reason)
        sys.exit(0)

print("ALLOW|Safe: every task scope resolves to a reviewed script under AF_TASK_SCRIPT_DIRS.")
' "$task_repo" "$task_dirs_raw")

    if [ -z "$decision" ]; then
        emit_task deny "Policy hard-deny: unrecognised task payload shape (classifier error); fail-closed. Point the task command at a reviewed script under AF_TASK_SCRIPT_DIRS (default .github/scripts)."
    fi

    decision_word="${decision%%|*}"
    decision_reason="${decision#*|}"
    if [ "$decision_word" = "DENY" ]; then
        emit_task deny "$decision_reason"
    else
        emit_task allow "$decision_reason"
    fi
fi

command_str=$(echo "$raw" | "$PYTHON" -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)

# For run_task the command is not in the payload at all -- it is resolved from
# tasks.json further down, once emit() is defined.
is_task_run=0
case "$tool_name" in run_task|runTask) is_task_run=1 ;; esac

if [ -z "$command_str" ] && [ "$is_task_run" -eq 0 ]; then
    echo '{}'
    exit 0
fi

# --- Load autonomy config (resolved by the shared preamble) ---
get_af_env() {
    # $1 = key, $2 = default
    af_conf_get "$1" "${2:-}"
}

level=$(get_af_env AUTONOMY_LEVEL balanced | tr '[:upper:]' '[:lower:]')
case "$level" in conservative|balanced|autonomous) ;; *) level=balanced ;; esac
protected=$(get_af_env PROTECTED_BRANCHES 'main,master,dev')
prot_alt=$(echo "$protected" | sed -E 's/[[:space:]]//g; s/,/|/g')
[ -z "$prot_alt" ] && prot_alt='main|master|dev'
cur_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
# Optional executable path prefix (.venv/bin/, .venv\Scripts\, ./, /usr/bin/) and .exe suffix.
path_pfx='(\S*[\\/])?'
exe='(\.exe)?'

# category resolver: override wins, else level default
cat_default() {
    # $1 = category name
    case "$level" in
        conservative)
            case "$1" in git_read|fs_read) echo auto ;; *) echo ask ;; esac ;;
        autonomous)
            case "$1" in git_read|fs_read|fs_write|tests|git_feature|git_merge|pkg|cloud_read) echo auto ;; *) echo ask ;; esac ;;
        *) # balanced
            case "$1" in git_read|fs_read|tests|git_feature|git_merge|cloud_read) echo auto ;; *) echo ask ;; esac ;;
    esac
}
resolve_cat() {
    # $1 = category name, $2 = env key
    local ov
    ov=$(get_af_env "$2" "" | tr '[:upper:]' '[:lower:]')
    if [ -n "$ov" ]; then echo "$ov"; else cat_default "$1"; fi
}
cat_git_read=$(resolve_cat git_read AUTONOMY_CAT_GIT_READ)
cat_git_feature=$(resolve_cat git_feature AUTONOMY_CAT_GIT_FEATURE)
cat_git_merge=$(resolve_cat git_merge AUTONOMY_CAT_GIT_MERGE)
cat_tests=$(resolve_cat tests AUTONOMY_CAT_TESTS)
cat_fs_read=$(resolve_cat fs_read AUTONOMY_CAT_FS_READ)
cat_pkg=$(resolve_cat pkg AUTONOMY_CAT_PKG_INSTALL)
cat_databricks=$(resolve_cat databricks AUTONOMY_CAT_DATABRICKS)
cat_cloud_read=$(resolve_cat cloud_read AUTONOMY_CAT_CLOUD_READ)
cat_fs_write=$(resolve_cat fs_write AUTONOMY_CAT_FS_WRITE)

emit() {
    # $1 = decision, $2 = reason
    # The reason now carries the command line itself, which routinely contains
    # quotes and backslashes. Interpolating those raw would produce invalid
    # JSON, and an unparsable verdict is indistinguishable from no verdict --
    # the gate would disarm itself precisely when it had something to say.
    local reason
    reason=$(printf '%s' "$2" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\r' | tr '\n' ' ')
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' "$1" "$reason"
    exit 0
}

# ===================== run_task -- resolve before classifying ===============
# The payload names a task; a name is not a command. The command lives in the
# project .vscode/tasks.json, so it is read back here and every scope is
# reconstructed into a command line. From that point on a task launch is
# classified by exactly the same tiers as a terminal command -- which is the
# point: run_task was a hole straight through the classifier. Anything that
# cannot be resolved answers ask, never silence: the gate says it could not
# judge instead of producing the same bytes as consent (issue #68).
# The JSON walk is delegated to Python (already a hard dependency here).
if [ "$is_task_run" -eq 1 ]; then
    task_run_out=$(printf '%s' "$raw" | "$PYTHON" -c '
import sys, json, os, re

tail = "The task launch could not be classified, so this needs a human decision. Check what the task runs in .vscode/tasks.json."

def ask(msg):
    print("ASK|Unclassified task launch: " + msg + " " + tail)
    sys.exit(0)

try:
    data = json.load(sys.stdin)
except Exception:
    ask("the payload is not valid JSON, so the task cannot be looked up.")

ti = data.get("tool_input") or {}
ws = str(ti.get("workspaceFolder") or "")
tid = str(ti.get("id") or "")
if not ws or not tid:
    ask("the payload carries no workspaceFolder/id, so the task cannot be looked up.")

path = os.path.join(ws, ".vscode", "tasks.json")
if not os.path.isfile(path):
    ask("no .vscode/tasks.json under " + ws + ", so task " + tid + " cannot be resolved to a command.")
try:
    fh = open(path, "r", encoding="utf-8-sig")
    doc = json.load(fh)
    fh.close()
except Exception:
    # tasks.json accepts JSONC in VS Code, so a comment or trailing comma
    # parses here as nothing at all. Unreadable is not the same as safe.
    ask(".vscode/tasks.json is not strict JSON (comments or trailing commas), so task " + tid + " cannot be resolved.")

# VS Code addresses a task as {type}: {label} -- captured ids look like
# shell: tests: all. Only the first type prefix is stripped; the label itself
# may contain a colon.
bare = re.sub(r"^[A-Za-z]+:\s+", "", tid)
task = None
for t in (doc.get("tasks") or []):
    if isinstance(t, dict) and str(t.get("label", "")) in (tid, bare):
        task = t
        break
if task is None:
    ask("no task labelled " + bare + " in .vscode/tasks.json.")

# Variables whose value is produced elsewhere (a prompt, a VS Code command, a
# setting) hide the payload from the classifier.
text = json.dumps(task)
for v in ("${input:", "${command:", "${config:"):
    if v in text:
        ask("task " + bare + " contains a " + v + "...} variable, so its effective command line is not visible here.")

# An OS-specific scope overrides the task scope, so every variant present must
# be classified -- reading only command classifies a decoy.
scopes = [task]
for o in ("windows", "linux", "osx"):
    if isinstance(task.get(o), dict):
        scopes.append(task[o])

lines = []
for o in scopes:
    opts = o.get("options")
    if isinstance(opts, dict) and opts.get("shell"):
        ask("task " + bare + " overrides options.shell, which moves the executed payload into the shell arguments where it cannot be classified.")
    c = o.get("command") or task.get("command")
    a = o.get("args") if o.get("args") is not None else task.get("args")
    if not c:
        continue
    line = str(c)
    if a:
        line = line + " " + " ".join([str(x) for x in a])
    line = line.strip()
    if line:
        lines.append(line)
if not lines:
    ask("task " + bare + " declares no command (composite or extension-provided task).")

# Newline-joined: the deny tier scans line by line and the allow tier splits on
# newlines, so every scope must clear the bar independently.
print("CMD")
print("\n".join(lines))
' 2>/dev/null)
    task_run_head=$(printf '%s\n' "$task_run_out" | head -n 1)
    case "$task_run_head" in
        CMD)
            command_str=$(printf '%s\n' "$task_run_out" | tail -n +2)
            ;;
        ASK*)
            emit ask "${task_run_head#ASK|}"
            ;;
        *)
            emit ask "Unclassified task launch: the task could not be resolved to a command line. This needs a human decision. Check what the task runs in .vscode/tasks.json."
            ;;
    esac
    if [ -z "$command_str" ]; then
        emit ask "Unclassified task launch: the resolved task command line is empty. This needs a human decision. Check what the task runs in .vscode/tasks.json."
    fi
fi

# Patterns are passed after -e: a pattern starting with a dash (e.g.
# --no-verify) would otherwise be parsed as a grep option, and the failing
# call would silently report "no match" -- a fail-open deny rule.
matches() { echo "$command_str" | grep -qEi -e "$1"; }
# ASK-tier scan runs on the quote-stripped command (set later) so quoted
# literals (e.g. a commit message) do not falsely trigger a rule.
matches_stripped() { echo "$stripped_guard" | grep -qEi -e "$1"; }

# ---------------------------------------------------------------------------
# Scan units (issue #62)
#
# A command line is not one string to be pattern-matched -- it is a sequence of
# statements, some of whose quoted arguments are data. Matching deny patterns
# against the raw text blocked real work: a commit message containing
# "--force", a probe whose JSON test data contained "Remove-Item -Recurse
# -Force". Worse, `(\S+\s+)*` in the git rules matched across a `;`, so a
# genuine `git add` in one statement joined up with prose in the next.
#
# Stripping quotes globally would be the wrong fix: the payload of
# `bash -c "..."` lives inside quotes and IS executed. So each statement
# becomes its own scan unit, quoted arguments that are themselves executed are
# promoted to units of their own, and quoted text is dropped only where it is
# unambiguously prose.
#
# Splitting and classification are delegated to Python (already a hard
# dependency here) because both need quote-aware scanning. Mode "segments"
# yields plain statements (TIER 2); mode "units" yields the deny-tier units.
# ---------------------------------------------------------------------------
SPLIT_PY='import sys, re
mode = sys.argv[1] if len(sys.argv) > 1 else "segments"
s = sys.stdin.read()

def split_top(t):
    out=[];cur=[];q=None;i=0
    while i<len(t):
        c=t[i]
        if q:
            cur.append(c)
            if c==q:q=None
            i+=1;continue
        if c=="\"" or c=="\x27":
            q=c;cur.append(c);i+=1;continue
        n=t[i+1] if i+1<len(t) else ""
        if (c=="&" and n=="&") or (c=="|" and n=="|"):
            out.append("".join(cur));cur=[];i+=2;continue
        if c==";" or c=="|" or c=="\n":
            out.append("".join(cur));cur=[];i+=1;continue
        cur.append(c);i+=1
    out.append("".join(cur))
    return [x.replace("\n"," ") for x in out]

segs = split_top(s)
if mode == "segments":
    sys.stdout.write("\n".join(segs))
    sys.exit(0)

DATA = re.compile(r"^\s*(echo|printf|Write-Host|Write-Output|Write-Error|Write-Verbose|Write-Debug)\b|^\s*git\s+(commit|tag|notes|stash)\b", re.I)
PAYLOAD = re.compile(r"(?:^|\s)(?:-c|--command|-Command|-e|--eval|-ScriptBlock|-ArgumentList|-Args|/c|/k|iex|Invoke-Expression|eval)\s+(?:\"([^\"]*)\"|\x27([^\x27]*)\x27)", re.I)
BARE = re.compile(r"^\s*(\"[^\"]*\"|\x27[^\x27]*\x27)\s*$")

def strip_quoted(seg):
    if "$(" in seg or "`" in seg:
        return seg
    return re.sub(r"\x27[^\x27]*\x27", "", re.sub(r"\"[^\"]*\"", "", seg))

units=[]
for seg in segs:
    if not seg.strip():
        continue
    units.append(strip_quoted(seg) if (BARE.match(seg) or DATA.search(seg)) else seg)
    for m in PAYLOAD.finditer(seg):
        payload = m.group(1) if m.group(1) is not None else m.group(2)
        for p in split_top(payload):
            if p.strip():
                units.append(p)
if not units:
    units=[s]
sys.stdout.write("\n".join(units))'

split_command() { printf '%s' "$1" | "$PYTHON" -c "$SPLIT_PY" "$2"; }

scan_units=$(split_command "$command_str" units)
# Never let a splitter failure blind the deny tier: fall back to the raw string.
[ -z "$(printf %s "$scan_units" | tr -d '[:space:]')" ] && scan_units="$command_str"
# grep matches line by line, so a unit is exactly one line and `$` in a pattern
# anchors to the end of that unit.
matches_unit() { printf '%s\n' "$scan_units" | grep -qEi -e "$1"; }

# ===================== TIER 1 -- DENY (hard) =====================
deny_msg="Policy hard-deny. The agent will not run this. If genuinely required, either (a) run it yourself -- the agent can prepare the exact command for you to paste and execute -- or (b) make a conscious decision to relax the autonomy policy in .github/af-env.conf."
deny_patterns=(
    'git\s+push\b.*(--force|-f)\b'
    "git\s+push\b.*(\s|:)($prot_alt)(\s|$)"
    'git\s+reset\s+--hard'
    'git\s+rebase\b'
    'git\s+branch\b.*--force\b'
    "git\s+branch\s+-d\b.*(\s|:)($prot_alt)(\s|$)"
    'git\s+add\s+(\S+\s+)*(--force|-f)(\s|$)'
    'git\s+add\s+(-\S+\s+)*\.(\s|$)'
    'git\s+add\s+(\S+\s+)*-A(\s|$)'
    '--no-verify'
    'rm\s+-r[f ].*(\s|=)(/|~|\*)'
    'Remove-Item.*-Recurse.*-Force'
    'dd\s+if=.*of=/dev/'
    'mkfs\.'
    'format\s+[A-Za-z]:'
    'chmod\s+-R\s+777'
)
# Rules about structure or payload content that legitimately spans units, and
# so stay scoped to the raw command line. Destructive SQL is deliberately here:
# SQL clients take it as a quoted argument, and a false deny on a commit message
# that mentions DROP TABLE is the lesser evil.
deny_patterns_raw=(
    '\|\s*(bash|sh|iex|Invoke-Expression)\b'
    'DROP\s+(TABLE|DATABASE)'
    'TRUNCATE\s+TABLE'
)
for p in "${deny_patterns[@]}"; do
    if matches_unit "$p"; then emit deny "$deny_msg"; fi
done
for p in "${deny_patterns_raw[@]}"; do
    if matches "$p"; then emit deny "$deny_msg"; fi
done
# Branch force-deletion (-D) needs a CASE-SENSITIVE check (grep without -i) so
# that the safe lowercase -d (merged-only) is not denied.
if printf '%s\n' "$scan_units" | grep -qE 'git[[:space:]]+branch[[:space:]]+(\S+[[:space:]]+)*-D([[:space:]]|$)'; then
    emit deny "$deny_msg"
fi
# Category-scoped deny (when autonomy policy sets a category to 'deny').
if [ "$cat_pkg" = "deny" ] && matches_unit '\bpip3?\s+(install|uninstall)\b|\bconda\s+(install|remove)\b'; then
    emit deny "$deny_msg"
fi
if [ "$cat_databricks" = "deny" ] && matches_unit '\bdatabricks\b'; then
    emit deny "$deny_msg"
fi

# ===================== TIER 2 -- ALLOW (segment-based) =====================
# The command is split into segments on ; && || | and auto-approved only when
# EVERY segment is individually safe. This lets common composites through
# (e.g. `cd ... ; pytest ... 2>&1 | Select-Object -Last 30`). DENY already
# scanned the whole string, so hidden dangerous segments are blocked above.
# Command substitution ($( ) / backticks) and file-write redirects (> file)
# are never auto-allowed.
sm() { printf '%s' "$SEG" | grep -qEi -e "$1"; }
is_safe_segment() {
    SEG="$(printf '%s' "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [ -z "$SEG" ] && return 0
    # strip a leading simple assignment ($x = ...) -- no side effect beyond its RHS
    SEG="$(printf '%s' "$SEG" | sed -E 's/^\$[[:alnum:]_:]+[[:space:]]*=[[:space:]]*//')"
    # strip a leading call operator (& "path/tool" ...) -- benign invocation wrapper
    SEG="$(printf '%s' "$SEG" | sed -E 's/^&[[:space:]]+//')"
    SEG="$(printf '%s' "$SEG" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    # file-write redirect (excludes fd duplication like 2>&1, >&1)
    if printf '%s' "$SEG" | grep -qE '>>?[[:space:]]*[^&[:space:]>]'; then
        if [ "$cat_fs_write" != "auto" ]; then return 1; fi
        # FS_WRITE=auto: strip the file redirect and vet the left command
        SEG="$(printf '%s' "$SEG" | sed -E 's/>>?[[:space:]]*[^[:space:]&>|]+//g' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
        [ -z "$SEG" ] && return 0
    fi
    # background / inline chaining operator ( & ) not handled by the split
    # ( & is not split on because it also appears in fd redirects like 2>&1 )
    if printf '%s' "$SEG" | grep -qE '(^|[^0-9>&])&([^&]|$)'; then return 1; fi
    sm '^(cd|Set-Location|pushd|popd|Push-Location|Pop-Location)\b' && return 0
    sm '^(Select-Object|Select-String|Sort-Object|Measure-Object|Out-String|Out-Host|Format-Table|Format-List|Get-Unique|Join-Path|Split-Path|Resolve-Path|more|wc|findstr|grep|ConvertFrom-Json|ConvertTo-Json)\b' && return 0
    sm '^[[:space:]]*[[:alnum:]._/-]+([[:space:]]+-{1,2}[[:alnum:]=.,_-]+)*[[:space:]]+--version\b' && return 0
    if [ "$cat_git_read" = "auto" ]; then
        sm '^\s*git\s+(status|diff|log|show|rev-parse|rev-list|remote|blame|describe|shortlog|for-each-ref|ls-files|config\s+--get|fetch)\b' && return 0
        # read-only config access: recognised read flags + at most one key, nothing after
        sm '^\s*git\s+config\s+(--(global|local|system|worktree|get|get-all|get-regexp|list|show-origin|show-scope)\s+)*[[:alnum:]._-]*\s*$' && return 0
        sm '^\s*git\s+stash\s+list\b' && return 0
        if sm '^\s*git\s+branch\b' && ! sm '\s-[dDmMcC]\b' && ! sm '--(delete|move|copy|force)\b'; then return 0; fi
        if sm '^\s*git\s+tag\b' && ! sm '\s-[adfsm]\b' && ! sm '--(delete|force|sign|annotate)\b' && ! sm '^\s*git\s+tag\s+[^\s-]'; then return 0; fi
    fi
    if [ "$cat_git_feature" = "auto" ]; then
        sm '^\s*git\s+commit\b' && return 0
        sm '^\s*git\s+add\s+\S' && return 0
        sm '^\s*git\s+(checkout|switch)\s+-[bc]\s+agent/' && return 0
        sm '^\s*git\s+(checkout|switch)\s+agent/' && return 0
        # switch to a branch (never touches files, so always safe)
        sm '^[[:space:]]*git[[:space:]]+switch[[:space:]]+[[:alnum:]_./-]+[[:space:]]*$' && return 0
        # checkout an existing ref (branch/tag/commit) -- verified so a file
        # pathspec (which would discard changes) is NOT auto-approved
        if printf '%s' "$SEG" | grep -qE '^[[:space:]]*git[[:space:]]+checkout[[:space:]]+[[:alnum:]_./-]+[[:space:]]*$'; then
            ref=$(printf '%s' "$SEG" | sed -E 's/^[[:space:]]*git[[:space:]]+checkout[[:space:]]+([[:alnum:]_./-]+)[[:space:]]*$/\1/')
            if git rev-parse --verify --quiet "${ref}^{commit}" >/dev/null 2>&1; then return 0; fi
        fi
        # delete a merged, non-protected branch (git -d refuses unmerged; -D/--force denied above)
        if sm '^\s*git\s+branch\s+(\S+\s+)*-d(\s|$)' && ! printf '%s' "$SEG" | grep -qE '\s-D\b' && ! sm '--force\b' && ! sm "(\s|:)($prot_alt)(\s|$)"; then return 0; fi
        if sm '^\s*git\s+push\b' && ! sm "(\s|:)($prot_alt)(\s|$)"; then
            if sm 'agent/'; then return 0; fi
            if [ -n "$cur_branch" ] && ! echo "$cur_branch" | grep -qxE "$prot_alt"; then return 0; fi
        fi
        sm '^\s*git\s+(restore|switch\s+agent/)\b' && return 0
    fi
    if [ "$cat_git_merge" = "auto" ]; then
        # reversible topology changes (pull/merge/cherry-pick/revert) -- reflog-recoverable
        sm '^\s*git\s+(pull|merge|cherry-pick|revert)\b' && return 0
    fi
    if [ "$cat_tests" = "auto" ]; then
        sm "^\s*${path_pfx}(pytest|mypy|pyright|tox|nox|radon|bandit|flake8|pylint|vulture|pip-audit)${exe}\b" && return 0
        sm "^\s*${path_pfx}python([0-9])?${exe}\s+-m\s+(pytest|mypy|pyright)\b" && return 0
        sm "^\s*${path_pfx}ruff${exe}\s+(check|format\s+--check)\b" && return 0
        sm 'run-tests' && return 0
    fi
    if [ "$cat_fs_read" = "auto" ]; then
        sm '^\s*(ls|dir|Get-ChildItem|cat|type|Get-Content|head|tail|Test-Path|pwd|Get-Location|where(\.exe)?|Get-Command|Get-Date|whoami|hostname|Get-Process|Get-Service|echo|Write-Output|Write-Host)\b' && return 0
        sm "^\s*${path_pfx}pip3?${exe}\s+(list|show|freeze|check)\b" && return 0
        sm '^\s*"?(\S*[\\/])?python([0-9])?(\.exe)?"?\s+-m\s+pip\s+(list|show|freeze|check)\b' && return 0
    fi
    if [ "$cat_pkg" = "auto" ]; then
        sm "^\s*${path_pfx}pip3?${exe}\s+(install|uninstall)\b" && return 0
        sm '^\s*python([0-9])?\s+-m\s+pip\s+(install|uninstall)\b' && return 0
        sm "^\s*${path_pfx}conda${exe}\s+(install|remove)\b" && return 0
    fi
    if [ "$cat_cloud_read" = "auto" ]; then
        # read-only cloud CLI; exclude anything touching secrets/credentials/tokens
        if ! printf '%s' "$SEG" | grep -qiE '(secret|credential|token|password|keyvault|get-access-token)'; then
            sm '^\s*databricks\s+[[:alnum:]_-]+\s+(list|get|ls|show)\b' && return 0
            sm '^\s*databricks\s+current-user\b' && return 0
            sm '^\s*az\s+.+\b(show|list)\b' && return 0
        fi
    fi
    if [ "$cat_databricks" = "auto" ]; then
        sm '^\s*databricks\b' && return 0
    fi
    # local filesystem writes (opt-in via AUTONOMY_CAT_FS_WRITE). Recursive/force
    # deletes and broad rm are hard-denied above, so only the safe subset is here.
    if [ "$cat_fs_write" = "auto" ]; then
        sm '^\s*(Out-File|Set-Content|Add-Content|Tee-Object|New-Item|mkdir|md|Move-Item|Copy-Item|mv|cp|touch)\b' && return 0
        if sm '^\s*(Remove-Item|rm|del|erase)\b' && ! sm '(-recurse|-force|\*)' && ! sm '(^|\s)-[rf]{1,2}\b'; then return 0; fi
    fi
    return 1
}

# Suppress auto-allow when the command uses grouping / subexpression /
# scriptblock metacharacters OUTSIDE quotes -- e.g. bash `(cmd)` runs a subshell
# and `Write-Host (Remove-Item x)` executes the inner command. Quote-strip first
# so conventional-commit messages like "fix(scope): ..." are not falsely blocked.
stripped_guard=$(printf '%s' "$command_str" | sed -E 's/"[^"]*"//g' | sed -E "s/'[^']*'//g")
if ! printf '%s' "$stripped_guard" | grep -qE '[`({]'; then
    seg_lines=$(split_command "$command_str" segments)
    any=0; allsafe=1
    while IFS= read -r seg; do
        [ -z "$(printf '%s' "$seg" | tr -d '[:space:]')" ] && continue
        any=1
        if ! is_safe_segment "$seg"; then allsafe=0; break; fi
    done <<SEGEOF
$seg_lines
SEGEOF
    if [ "$any" -eq 1 ] && [ "$allsafe" -eq 1 ]; then
        emit allow 'Safe: every command segment is read-only or a known-safe operation.'
    fi
fi

# ===================== TIER 3 -- ASK (durable change) =====================
#
# A confirmation prompt is a question put to a human, and a question that does
# not say what it is about cannot be answered -- it can only be waved through.
# The whole tier used to share one sentence ("This command makes a durable
# change") for eleven different rules, naming neither the rule that fired nor
# the command it fired on, while the deny tier next door has been specific all
# along (issue #78). Each rule now says what it will actually do, and the
# command is echoed so the answer is about the command rather than the category.
ask_patterns=(
    'git\s+merge\b'
    'git\s+(checkout|switch)\b'
    'git\s+tag\b'
    '\bpip3?\s+(install|uninstall)\b'
    '\bconda\s+(install|remove)\b'
    '\bruff\s+format\b'
    '\bdatabricks\b.*\b(submit|run|create|update|delete|import|export|deploy)\b'
    '\baz\b.*\b(create|set|delete|update|deploy)\b'
    'Remove-Item\b'
    '(^|\s)rm\b'
    '(Move-Item|Copy-Item|New-Item|mkdir|mv|cp)\b'
)
# Index-aligned with ask_patterns.
ask_reasons=(
    "'git merge' rewrites the working tree and may leave conflict markers in tracked files"
    "'git checkout'/'git switch' changes the checked-out branch, and with a path argument it discards uncommitted changes to that path"
    "'git tag' creates or moves a tag, which is a release marker others may already rely on"
    'pip install/uninstall changes the environment for everything that uses it, not just this task'
    'conda install/remove changes the environment for everything that uses it, not just this task'
    "'ruff format' rewrites source files in place"
    'this Databricks CLI call acts on a remote workspace, where the effect is outside this repository and outside git'
    'this Azure CLI call changes cloud resources, where the effect is outside this repository and may cost money'
    "'Remove-Item' deletes files or directories"
    "'rm' deletes files or directories"
    'this writes to the filesystem (creates, moves or copies files)'
)
# Echoing the command is the point of the prompt, but an unbounded string in a
# dialog is its own way of hiding information.
shown=$(printf '%s' "$command_str" | tr '\n\t' '  ' | sed -E 's/[[:space:]]+/ /g')
if [ "${#shown}" -gt 300 ]; then shown="${shown:0:297}..."; fi
for i in "${!ask_patterns[@]}"; do
    if matches_stripped "${ask_patterns[$i]}"; then
        emit ask "Durable change: ${ask_reasons[$i]}. Confirm it is intentional. Command: $shown"
    fi
done

echo '{}'
