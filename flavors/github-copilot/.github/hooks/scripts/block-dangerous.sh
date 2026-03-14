#!/usr/bin/env bash
# PreToolUse hook: Requires user confirmation for dangerous terminal commands.
# Input:  JSON via stdin with tool_name and tool_input
# Output: JSON with permissionDecision="ask" if dangerous pattern detected

# Find a Python interpreter for JSON parsing
PYTHON=$(command -v python3 2>/dev/null || command -v python 2>/dev/null || echo "")

raw=$(cat)

# If no Python available, allow everything (can't parse safely)
if [ -z "$PYTHON" ]; then
    echo '{}'
    exit 0
fi

# Extract tool_name
tool_name=$(echo "$raw" | "$PYTHON" -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

# Only inspect terminal commands
case "$tool_name" in
    *terminal*|*Terminal*) ;;
    *) echo '{}'; exit 0 ;;
esac

# Extract command string
command_str=$(echo "$raw" | "$PYTHON" -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)

if [ -z "$command_str" ]; then
    echo '{}'
    exit 0
fi

# Check dangerous patterns
dangerous_patterns=(
    'rm\s+-r[f ]'
    'DROP\s+(TABLE|DATABASE)'
    'TRUNCATE\s+TABLE'
    'git\s+push\b'
    'git\s+merge\b'
    'git\s+branch\s+-[dD]\b'
    'git\s+rebase\b'
    'git\s+reset\s+--hard'
    'mkfs\.'
    'dd\s+if=.*of=/dev/'
    '--no-verify'
    'chmod\s+-R\s+777'
    'git\s+add\s+.*(-f|--force)'       # bypass .gitignore
    'git\s+add\s+(-\S+\s+)*\.$'      # git add . (banned wildcard)
    'git\s+add\s+.*-A'                 # git add -A (banned wildcard)
)

for pattern in "${dangerous_patterns[@]}"; do
    if echo "$command_str" | grep -qEi "$pattern"; then
        cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"Safety hook: command matches dangerous pattern. Please confirm this is intentional."}}
EOF
        exit 0
    fi
done

echo '{}'
