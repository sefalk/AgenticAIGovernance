#!/usr/bin/env bash
# SessionStart hook: Injects git and environment context into the agent session.
# Input:  JSON via stdin (common fields + source)
# Output: JSON with additionalContext

# Consume stdin (required even if unused)
cat > /dev/null

# Gather context
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
commit=$(git log -1 --format='%h %s' 2>/dev/null || echo "unknown")
py_ver=$(python3 --version 2>/dev/null || python --version 2>/dev/null || echo "unknown")
project=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "unknown")

context="Project: ${project} | Branch: ${branch} | Last commit: ${commit} | ${py_ver}"

# Return JSON — escape double quotes in context for safety
context_escaped=$(echo "$context" | sed 's/"/\\"/g')
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$context_escaped"
