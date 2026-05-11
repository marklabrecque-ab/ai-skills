#!/bin/bash
# Post-commit hook: appends a summary entry to ~/daily_reports/{date}.md
# Triggered by Claude Code PostToolUse hook after "git commit" commands
# The hook's "if" filter ensures this only runs for git commit commands.

set -euo pipefail

# Consume stdin (hook sends JSON payload, but we read directly from git)
cat > /dev/null

# Get commit details from git
commit_sha=$(git log -1 --format="%h" 2>/dev/null) || exit 0
commit_msg=$(git log -1 --format="%s" 2>/dev/null) || exit 0
repo_name=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null) || repo_name="unknown"
timestamp=$(date "+%H:%M")
date_file=$(date "+%Y-%m-%d-%A")
report_dir="$HOME/daily_reports"
report_file="${report_dir}/${date_file}.md"

# Create report file with date header if it doesn't exist
if [ ! -f "$report_file" ]; then
  echo "# Daily Report — $(date '+%Y-%m-%d %A')" > "$report_file"
  echo "" >> "$report_file"
fi

# Deduplicate: skip if this commit hash is already logged today
if grep -qF "$commit_sha" "$report_file" 2>/dev/null; then
  exit 0
fi

# Extract ticket references (#NNN) from the commit subject so the timesheet
# skill's parser hits the authoritative `**Tickets:**` path instead of falling
# back to a regex scan. Multiple tickets are joined with ", " in source order.
tickets=$(printf '%s\n' "$commit_msg" | { grep -oE '#[0-9]+' || true; } | awk '!seen[$0]++' | paste -sd, - | sed 's/,/, /g')

# Append entry
{
  printf '\n### %s — %s\n' "$timestamp" "$repo_name"
  if [ -n "$tickets" ]; then
    printf '**Tickets:** %s\n' "$tickets"
  fi
  printf '%s (%s)\n' "$commit_msg" "$commit_sha"
} >> "$report_file"
