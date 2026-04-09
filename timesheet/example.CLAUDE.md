# Timesheet Skill Setup

This skill fills out Harvest timesheets from daily log files that are automatically generated as you work. Two pieces need to be configured:

## 1. Harvest API credentials

Add your Harvest credentials to `~/.claude/settings.json` under the `env` key:

```json
{
  "env": {
    "HARVEST_TOKEN": "your-harvest-personal-access-token",
    "HARVEST_ACCOUNT_ID": "your-harvest-account-id"
  }
}
```

You can create a Personal Access Token at https://id.getharvest.com/developers.

## 2. Daily log hook

The daily log is generated automatically by a Claude Code hook that fires after every `git commit`. It appends an entry to `~/daily_reports/{YYYY-MM-DD-DayName}.md` with the timestamp, repo name, and commit message.

### Install the hook script

Copy the hook script to your Claude hooks directory:

```bash
mkdir -p ~/.claude/hooks
cp hooks/daily-log.sh ~/.claude/hooks/daily-log.sh
chmod +x ~/.claude/hooks/daily-log.sh
```

### Register the hook in Claude Code settings

Add the following to `~/.claude/settings.json` under the `hooks` key:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/daily-log.sh",
            "if": "Bash(git commit *)",
            "timeout": 5000
          }
        ]
      }
    ]
  }
}
```

This tells Claude Code to run `daily-log.sh` after any Bash tool call that matches `git commit *`.

## How it works

1. You work normally, making commits via Claude Code
2. Each commit automatically appends an entry to `~/daily_reports/2026-04-09-Thursday.md`
3. Entries look like: `### 14:32 — my-project` / `Fix login bug (#42) (a1b2c3d)`
4. When you're ready to log time, invoke the timesheet skill and it reads these files to create Harvest entries

## Daily report format

```markdown
# Daily Report — 2026-04-09 Thursday

### 08:03 — wilderness-committee
#340 Disable google_analytics module and update GTM config (e0ac72f3)

### 09:15 — client-portal
Fix authentication redirect loop (b4d8e2a1)
```

The skill groups entries by project per day and creates one Harvest time entry per project.
