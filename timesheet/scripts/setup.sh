#!/usr/bin/env bash
# Scaffolds the shared config directory used by the `timesheet` and
# `value-estimates` plugins: ~/daily_reports/meta/projects.yml and
# ~/daily_reports/meta/local-context.md.
#
# Idempotent — never overwrites existing files. Run once after enabling the
# plugin. Edit the generated files to match your Harvest + GitLab setup.
set -euo pipefail

REPORTS_DIR="${DAILY_REPORTS_DIR:-$HOME/daily_reports}"
META_DIR="$REPORTS_DIR/meta"

mkdir -p "$META_DIR"

PROJECTS_FILE="$META_DIR/projects.yml"
if [[ ! -f "$PROJECTS_FILE" ]]; then
  cat > "$PROJECTS_FILE" <<'YAML'
# Project map shared by the `timesheet` and `value-estimates` plugins.
#
# Each entry supports:
#   harvest:      Official Harvest project name (used to match the Harvest API).
#   gitlab:       GitLab project path (e.g. "group/subgroup/repo").
#   log_aliases:  Tokens used in daily report markdown to identify this project.
#   internal:     true on the single "daily admin" / fallback project.
#   admin_task:   Task name on the internal project (e.g. "General").
#   excluded:     true to silently skip this project (no Harvest entries created).
#
# Examples — replace with your own projects:

# - harvest: "Example Client Portal"
#   gitlab: "example/client-portal"
#   log_aliases: [portal, clientportal]

# - harvest: "[INT] Internal"
#   internal: true
#   admin_task: "General"
#   log_aliases: [admin, internal]

# - harvest: "Open-source contributions"
#   excluded: true
#   log_aliases: [oss]
YAML
  echo "Created $PROJECTS_FILE"
else
  echo "Exists, skipped: $PROJECTS_FILE"
fi

LOCAL_FILE="$META_DIR/local-context.md"
if [[ ! -f "$LOCAL_FILE" ]]; then
  cat > "$LOCAL_FILE" <<'MD'
# Local Context

Per-machine settings for the `timesheet` and `value-estimates` plugins.

- **Daily reports path:** `~/daily_reports/` (override by exporting `DAILY_REPORTS_DIR`)
MD
  echo "Created $LOCAL_FILE"
else
  echo "Exists, skipped: $LOCAL_FILE"
fi

cat <<'INFO'

Next steps:
  1. Edit ~/daily_reports/meta/projects.yml — add your Harvest projects.
  2. Export HARVEST_ACCOUNT_ID and HARVEST_TOKEN in your shell environment
     (see skills/timesheet/example.zshenv for a template).
  3. Optional: export GITLAB_HOST + GITLAB_TOKEN if you use the value-estimates plugin.
INFO
