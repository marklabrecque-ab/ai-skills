---
name: timesheet
description: "Fill out Harvest timesheet from daily log files. Use this skill whenever the user mentions timesheets, time tracking, time entries, logging hours, filling out Harvest, submitting hours, or anything related to recording work time — even if they just say 'log my time' or 'do my timesheet'. Also trigger when the user asks to sync daily reports/logs to Harvest."
---

# Timesheet Skill

Create Harvest time entries from the user's daily report markdown files in `~/daily_reports/`.

## Arguments

Check the skill arguments for flags before proceeding:

- `--analyze [N]` — Run the **Analyze** flow (see below) instead of the normal entry-creation flow. `N` is an optional number of days to look back (default: 30). If this flag is present, skip straight to the Analyze section.

If no `--analyze` flag is present, proceed with the normal flow starting at Step 1.

---

## Analyze flow

When `--analyze` is passed, check Harvest for weekdays with low hours logged.

### Analyze Step 1: Determine lookback period

If the user passed a number after `--analyze` (e.g. `--analyze 60`), use that as the number of days. Otherwise, ask the user how many days to look back — but let them press enter / skip to accept the default of 30 days.

Calculate `START_DATE` as today minus N days, and `END_DATE` as **yesterday** (today minus 1). Today is excluded since the day isn't over yet.

### Analyze Step 2: Fetch time entries and identify gaps

Fetch all time entries for the date range in a **single Bash call** using Python. The Harvest API paginates at 100 entries per page, so handle pagination. Also fetch the user ID and company base URI for generating direct links.

**Important:** Use Python (`urllib.request` + `json`) for any Harvest API call that returns time entries. The `notes` field can contain literal newlines that break `jq`. The `jq` tool is fine for endpoints that don't return notes (e.g., project assignments, company info).

```bash
python3 -c "
import urllib.request, json, os
from datetime import datetime, timedelta

token = os.environ['HARVEST_TOKEN']
account_id = os.environ['HARVEST_ACCOUNT_ID']
headers = {
    'Authorization': f'Bearer {token}',
    'Harvest-Account-Id': account_id,
    'User-Agent': 'Claude-Timesheet-Skill'
}

def api_get(url):
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())

# Get base URI and user ID for day links
base_uri = api_get('https://api.harvestapp.com/v2/company')['base_uri']
user_id = api_get('https://api.harvestapp.com/v2/users/me')['id']

# Paginate time entries
hours_by_date = {}
page = 1
while True:
    data = api_get(f'https://api.harvestapp.com/v2/time_entries?from=START_DATE&to=END_DATE&page={page}')
    for entry in data['time_entries']:
        d = entry['spent_date']
        hours_by_date[d] = hours_by_date.get(d, 0) + entry['hours']
    if not data.get('next_page'):
        break
    page = data['next_page']

# Enumerate weekdays and find gaps
start = datetime.strptime('START_DATE', '%Y-%m-%d')
end = datetime.strptime('END_DATE', '%Y-%m-%d')
d = start
weekday_count = 0
while d <= end:
    if d.weekday() < 5:  # Mon-Fri
        weekday_count += 1
        ds = d.strftime('%Y-%m-%d')
        day_name = d.strftime('%a')
        total = hours_by_date.get(ds, 0)
        if total < 6:
            ymd = d.strftime('%Y/%m/%d')
            status = 'Missing' if total == 0 else 'Low'
            print(f'{ds}|{day_name}|{total}|{status}|{base_uri}/time/day/{ymd}/{user_id}')
    d += timedelta(days=1)

print(f'WEEKDAY_COUNT={weekday_count}')
"
```

### Analyze Step 3: Print report

From the data, identify all weekdays with < 6 hours (or 0 hours). Display a markdown table sorted by date. Each row includes a direct link to that day in Harvest.

The Harvest day URL format is: `{BASE_URI}/time/day/{YYYY}/{MM}/{DD}/{USER_ID}`

| Date | Day | Hours | Status | Link |
|------|-----|-------|--------|------|
| 2026-03-15 | Mon | 0.0 | Missing | [view](https://example.harvestapp.com/time/day/2026/03/15/123456) |
| 2026-03-18 | Thu | 4.0 | Low | [view](https://example.harvestapp.com/time/day/2026/03/18/123456) |

- **Missing** = 0 hours
- **Low** = greater than 0 but less than 6 hours

End with a summary line: e.g., "3 weekdays with < 6 hours out of 22 weekdays in range."

---

## Normal flow

### Overview

The user keeps daily work logs as markdown files. This skill reads those logs for a given date range, groups entries by project per day, matches each to a Harvest project, and creates one Harvest time entry per project per day — always 1 hour, with a combined summary comment covering all log entries for that project on that day.

## Credentials

The Harvest API credentials are available as environment variables:
- `HARVEST_TOKEN` — Personal Access Token
- `HARVEST_ACCOUNT_ID` — Harvest account ID

These are set in `~/.claude/settings.json` under the `env` key.

## Step 0: Load local context

Read `.local-context.md` from the skill directory (the directory containing this SKILL.md file). This file contains user-specific configuration:

- **Excluded projects** — project names to silently skip (never create time entries for these)
- **Internal project** — the Harvest project name used for the daily admin entry and as a fallback for unmatched log entries
- **Admin task name** — the task name on the internal project for the admin entry

If the file doesn't exist, tell the user to copy `.local-context.example.md` to `.local-context.md` and customize it, then stop.

## Step 1: Determine the date range

If the user hasn't specified dates, ask them what time period they want to log. Common patterns:
- "today" / "yesterday"
- "this week" / "last week"
- "March 10-14"
- A specific date like "Friday"

Convert relative references to absolute dates. The daily report filenames follow the pattern `{YYYY-MM-DD}-{DayOfWeek}.md`.

## Step 2: Fetch all data in a single call

Gather existing Harvest entries, project assignments, and daily report contents in **one Bash call**. Use `jq` for project assignments (safe — no notes field) and Python for time entries (notes field contains literal newlines that break `jq`).

Replace `START_DATE` and `END_DATE` with the first and last dates of the range, and list the date glob patterns in the `for` loop.

```bash
echo "=== EXISTING ==="
python3 -c "
import urllib.request, json, os
headers = {
    'Authorization': 'Bearer ' + os.environ['HARVEST_TOKEN'],
    'Harvest-Account-Id': os.environ['HARVEST_ACCOUNT_ID'],
    'User-Agent': 'Claude-Timesheet-Skill'
}
dates = set()
page = 1
while True:
    req = urllib.request.Request(
        f'https://api.harvestapp.com/v2/time_entries?from=START_DATE&to=END_DATE&page={page}',
        headers=headers)
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read())
    for e in data['time_entries']:
        dates.add(e['spent_date'])
    if not data.get('next_page'):
        break
    page = data['next_page']
print(json.dumps(sorted(dates)))
"

HEADERS=(-H "Authorization: Bearer $HARVEST_TOKEN" \
         -H "Harvest-Account-Id: $HARVEST_ACCOUNT_ID" \
         -H "User-Agent: Claude-Timesheet-Skill")

echo "=== PROJECTS ==="
curl -s "https://api.harvestapp.com/v2/users/me/project_assignments?is_active=true" \
  "${HEADERS[@]}" | jq '[.project_assignments[] | {
    name: .project.name,
    id: .project.id,
    tasks: [.task_assignments[] | {name: .task.name, id: .task.id}]
  }]'

echo "=== REPORTS ==="
for f in ~/daily_reports/START_DATE-*.md ~/daily_reports/NEXT_DATE-*.md; do
  [ -f "$f" ] && echo "--- $(basename "$f") ---" && cat "$f"
done
```

**If any entries already exist for a given date** (present in the `EXISTING` array), **skip that entire day.** Do not create any new entries for it. Mention skipped days in the summary table so the user knows.

If a daily report file doesn't exist for a given date, skip it silently — weekends and days off won't have files.

## Step 3: Parse and group entries

Each log file contains entries under `###` headers. Entries include a project identifier in one of these formats:
- `**Project**: project/name` or `**Project:** project/name`
- `### date — project/name` (project in the header itself)
- `Project: project/name` (plain text, no bold)
- Freeform mention like `- sideproject / api` at the end

Group all entries by (date, project). Each group becomes a single Harvest time entry (1 hour). For each group, format the notes as a list — one line per log entry, each prefixed with `- ` and a trailing newline. Use the `###` header title (trimmed of timestamps and project names) as each list item. For example:

```
- Search analytics Playwright verification tests
- Auto-detect base URL in Playwright tests
- Fix search tracking selector bug
```

### Exclusion rule

Silently skip any entry whose project name matches one of the **excluded projects** from `.local-context.md` (case-insensitive). Never create Harvest time entries for excluded projects.

If an entry has no identifiable project, assign it to the fallback bucket (see Step 4).

## Step 4: Resolve Harvest projects

Use the `PROJECTS` data already fetched in Step 2 (which contains project name, ID, and task assignments for each active project).

From this data:
1. Build a lookup of project names to IDs
2. Find the "Development" task ID (search task assignments for a task named "Development")
3. Fuzzy-match each log project name against the Harvest project names — match on keywords, ignoring case and punctuation. For example, "clientportal" should match "Client Portal" or similar.
4. Identify the **internal project** (from `.local-context.md`) — find its ID in the project list. This is used for two purposes:
   - **Fallback**: any log entry whose project can't be matched gets assigned here.
   - **Daily admin entry**: for every **weekday** (Mon–Fri) being processed, automatically add a 1-hour entry to this project with the **admin task** (from `.local-context.md`) and a blank comment. This entry should always appear in the summary table. Do **not** add an admin entry on weekends (Sat/Sun), even if the user logged work on those days.

The API paginates at 100 results. If `next_page` is present in the Step 2 project response, fetch subsequent pages in a follow-up call. In practice, most users have fewer than 100 active project assignments.

Before creating any entries, show the user a summary table:

| Date | Log Project | Harvest Project | Hours | Summary |
|------|------------|-----------------|-------|---------|
| 2026-03-25 | clientportal/api | Client Portal - API | 1.0 | - Config cleanup<br>- PHPUnit setup |
| 2026-03-25 | (admin) | *(internal project)* | 1.0 | |

Ask the user to confirm before proceeding. This matters because fuzzy matching can produce wrong mappings.

## Step 5: Create time entries

For all confirmed entries, create time entries via POST in a **single Bash call** using Python. The account uses duration-based tracking (not timestamp timers). Python avoids the `jq` parse errors caused by newlines in notes fields.

Build a Python script with all entries as a list of dicts. For example:

```bash
python3 -c "
import urllib.request, json, os

token = os.environ['HARVEST_TOKEN']
account_id = os.environ['HARVEST_ACCOUNT_ID']
headers = {
    'Authorization': f'Bearer {token}',
    'Harvest-Account-Id': account_id,
    'User-Agent': 'Claude-Timesheet-Skill',
    'Content-Type': 'application/json'
}

entries = [
    {'project_id': 111, 'task_id': 222, 'spent_date': '2026-03-23', 'hours': 1.0, 'notes': '- Task one\n- Task two'},
    {'project_id': 111, 'task_id': 333, 'spent_date': '2026-03-23', 'hours': 1.0, 'notes': ''},
    # ... one dict per entry
]

for entry in entries:
    try:
        req = urllib.request.Request(
            'https://api.harvestapp.com/v2/time_entries',
            data=json.dumps(entry).encode(),
            headers=headers,
            method='POST')
        with urllib.request.urlopen(req) as resp:
            result = json.loads(resp.read())
            print(f\"OK|{result['spent_date']}|{result['project']['name']}|{result['hours']}\")
    except urllib.error.HTTPError as e:
        body = json.loads(e.read())
        print(f\"FAIL|{e.code}|{body.get('message', 'unknown error')}\")
"
```

This produces compact output like:
```
OK|2026-03-23|Client Portal - API|1.0
OK|2026-03-23|Acme Corp [INT] Internal|1.0
FAIL|422|Project is archived
```

If any entry fails, report the error and continue with the rest.

## Step 6: Report results

After all entries are created, show a final summary:
- How many entries were created
- Any that failed and why
- Any log entries that were skipped (excluded projects, no project match, etc.)
