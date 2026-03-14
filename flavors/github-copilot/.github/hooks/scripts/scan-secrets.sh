#!/usr/bin/env bash
# PostToolUse hook: Scan edited files for hardcoded secrets.
#
# Uses gitleaks if available, falls back to regex pattern matching.
# Blocking — exits with code 1 when secrets are detected (HARD gate).

set -uo pipefail

raw=$(cat)
tool_name=$(echo "$raw" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null || echo "")

if ! echo "$tool_name" | grep -qiE 'edit|create|write|file'; then
    echo '{}'
    exit 0
fi

file_path=$(echo "$raw" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('filePath',''))" 2>/dev/null || echo "")

if [ -z "$file_path" ] || [ ! -f "$file_path" ]; then
    echo '{}'
    exit 0
fi

# Try gitleaks
if command -v gitleaks &>/dev/null; then
    result=$(gitleaks detect --no-git --source "$file_path" --no-color 2>&1) || true
    if [ $? -ne 0 ]; then
        echo "{\"gate\": \"secret-scan\", \"status\": \"FAIL\", \"tool\": \"gitleaks\", \"file\": \"$file_path\"}"
        exit 1
    fi
    echo '{}'
    exit 0
fi

# Fallback: grep for common patterns
findings=""
if grep -qE 'AKIA[0-9A-Z]{16}' "$file_path" 2>/dev/null; then
    findings="AWS Key"
fi
if grep -qiE '(password|secret|token|api_key)\s*[:=]\s*["'"'"'][^\s"'"'"']{8,}' "$file_path" 2>/dev/null; then
    findings="${findings:+$findings, }Generic Secret"
fi
if grep -q 'BEGIN.*PRIVATE KEY' "$file_path" 2>/dev/null; then
    findings="${findings:+$findings, }Private Key"
fi

if [ -n "$findings" ]; then
    echo "{\"gate\": \"secret-scan\", \"status\": \"FAIL\", \"tool\": \"regex-fallback\", \"file\": \"$file_path\", \"patterns\": \"$findings\"}"
    exit 1
fi

echo '{}'
exit 0
