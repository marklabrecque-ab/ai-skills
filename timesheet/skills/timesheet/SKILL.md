---
name: timesheet
description: "Fill out Harvest timesheet from daily log files. Use this skill whenever the user mentions timesheets, time tracking, time entries, logging hours, filling out Harvest, submitting hours, or anything related to recording work time — even if they just say 'log my time' or 'do my timesheet'. Also trigger when the user asks to sync daily reports/logs to Harvest."
---

# Timesheet Skill

Create Harvest time entries from the user's daily report markdown files in `~/daily_reports/`.

## Arguments

Check the skill arguments for flags before proceeding:

- `--analyze [N]` — Run the **Analyze** flow (see below) instead of the normal entry-creation flow. `N` is an optional number of days to look back (default: 30). If this flag is present, skip straight to the Analyze section.
- `--dry-run` — Walk Steps 1–4 normally, print the planned-entries summary table, then **stop**. Do not POST to Harvest, do not update `tickets.json`. Used for evals and for previewing what a run would do.

**Environment overrides (testing/eval support):**
- `DAILY_REPORTS_DIR` — if set, use this path instead of `~/daily_reports/` for both daily report files and the `meta/` config dir. Lets eval fixtures live entirely outside the user's real reports.

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

The user keeps daily work logs as markdown files. This skill reads those logs for a given date range, groups entries by ticket within project per day, matches each to a Harvest project, and creates one Harvest time entry per ticket per project per day — always `0.02h` (≈1 minute) as a placeholder the user adjusts to actuals later, with a combined summary comment covering all log entries for that ticket on that day. Multiple commits on the same ticket on the same day collapse into a single entry; commits without a ticket number are grouped together as one no-ticket entry per project per day; entries that touch multiple tickets duplicate (full placeholder per ticket — they don't split).

## Credentials

The Harvest API credentials are available as environment variables:
- `HARVEST_TOKEN` — Personal Access Token
- `HARVEST_ACCOUNT_ID` — Harvest account ID

These are exported from `~/.zshenv` (see `example.zshenv` in this skill directory for a template).

## Step 0: Load shared config

Read two files from `~/daily_reports/meta/`:

- **`projects.yml`** — shared project map (used by every skill that touches Harvest / GitLab / daily logs). Each entry can carry: `harvest` (official name), `gitlab` (project path), `log_aliases` (tokens used in daily logs), `internal: true` (the daily admin / fallback project), `admin_task` (task name on the internal project), `excluded: true` (silently skip). Parse with PyYAML or a small custom parser — entries are simple key/value blocks.
- **`local-context.md`** — per-machine bits that aren't shared (currently just the daily reports path; defaults to `~/daily_reports/`).

If `projects.yml` is missing, tell the user to create `~/daily_reports/meta/projects.yml` (use `local-context.example.md` as a starting reference for `local-context.md`) and stop.

From `projects.yml`, derive:
- **Excluded projects** — every entry with `excluded: true`. Match against log project names case-insensitively, against both `log_aliases` and `harvest` (when present).
- **Internal project** — the single entry with `internal: true`. Its `harvest` value is the daily admin project; its `admin_task` is the task name to use.

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

Extract ticket references from each entry. Sources, in priority order:

1. **`**Tickets:**` line** in the entry body (e.g. `**Tickets:** #189` or `**Tickets:** #189, #194`). Authoritative — use it and skip the regex scan.
2. **Regex scan** of the entry body for `#NNN` patterns (`#189`, `(#189)`, `ticket #189`). Capture all distinct IDs.
3. **No reference found.** Prompt the user inline: *"entry on YYYY-MM-DD '<header>' has no ticket — link one? (enter a `#NNN`, or press enter to leave unlinked)"*. If the user supplies a ticket, treat it as if it had been on a `**Tickets:**` line. If they skip, the entry goes into a no-ticket bucket for that (date, project).

Backfilling user-supplied tickets back into the markdown source is **out of scope** for now — see the Roadmap section. The prompt only collects the ticket for this run.

**Multiple tickets on one entry** → duplicate the entry into each ticket bucket (do **not** split the placeholder). Each ticket gets its own full-placeholder entry; the same `###` header text appears as a list item under every ticket it touched.

Group all entries by (date, project, ticket). Each group becomes a single Harvest time entry. For each group, format the notes as a list — one line per log entry, each prefixed with `- ` and a trailing newline. Use the `###` header title and/or commit subject (trimmed of timestamps, project names, and the leading `#NNN` token) as each list item. For example, for ticket #265:

```
- Update site search placeholder to 'Search Island Health'
- Fix /search clear button position and remove duplicate
- Migrate search asset_injector CSS into theme custom-overrides.css
```

Multiple commits on the same ticket on the same day collapse into one entry. A merge commit or chore-only entry with no ticket reference (and that the user opts not to link) lands in the no-ticket bucket for its project.

### Exclusion rule

Silently skip any entry whose project name matches one of the **excluded projects** from `.local-context.md` (case-insensitive). Never create Harvest time entries for excluded projects.

If an entry has no identifiable project, assign it to the fallback bucket (see Step 4).

## Step 4: Resolve Harvest projects

Use the `PROJECTS` data already fetched in Step 2 (which contains project name, ID, and task assignments for each active project).

From this data:
1. Build a lookup of project names to IDs
2. Find the "Development" task ID (search task assignments for a task named "Development")
3. Match each log project name against entries in `projects.yml` — first by `log_aliases` (exact, case-insensitive), then by fuzzy match against `harvest` (keywords, ignoring case/punctuation). The matched entry's `harvest` field maps to a Harvest project ID via the lookup from step 1. For example, log alias `ih` resolves to `Modernization of Island Health’s Digital Entry Point...`, which maps to a project ID in Harvest.
4. Identify the **internal project** (the entry with `internal: true` in `projects.yml`) — find its ID in the project list. This is used for two purposes:
   - **Fallback**: any log entry whose project can't be matched gets assigned here.
   - **Daily admin entry**: for every **weekday** (Mon–Fri) being processed, automatically add a 0.02h entry to this project with the **admin task** from `projects.yml` and a blank comment. This entry should always appear in the summary table. Do **not** add an admin entry on weekends (Sat/Sun), even if the user logged work on those days.

**Placeholder duration:** every entry created by this skill — per-ticket, no-ticket, and admin — uses `0.02h` (≈1 minute). The user adjusts each entry's duration to actuals later in the Harvest UI. The placeholder is intentionally tiny so untouched entries are obvious.

The API paginates at 100 results. If `next_page` is present in the Step 2 project response, fetch subsequent pages in a follow-up call. In practice, most users have fewer than 100 active project assignments.

Before creating any entries, show the user a summary table:

| Date | Log Project | Harvest Project | Ticket | Hours | Summary |
|------|------------|-----------------|--------|-------|---------|
| 2026-03-25 | clientportal/api | Client Portal - API | #142 | 0.02 | - Config cleanup<br>- PHPUnit setup |
| 2026-03-25 | clientportal/api | Client Portal - API | (none) | 0.02 | - Merge release branch |
| 2026-03-25 | (admin) | *(internal project)* | — | 0.02 | |

Ask the user to confirm before proceeding. This matters because fuzzy matching can produce wrong mappings.

## Step 5: Create time entries

For all confirmed entries, create time entries via POST in a **single Bash call** using Python. The account uses duration-based tracking (not timestamp timers); supplying `hours` without `started_time` does not start a timer (`is_running: false` in the response). Python avoids the `jq` parse errors caused by newlines in notes fields.

Each entry's `notes` should begin with the ticket reference (`#NNN`) on its own line, followed by the bulleted commit list. This makes per-ticket aggregation in downstream tools (value-estimates, future report skills) reliable. For the no-ticket bucket and the admin entry, omit the leading `#NNN` line.

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
    {'project_id': 111, 'task_id': 222, 'spent_date': '2026-03-23', 'hours': 0.02, 'notes': '#142\n- Task one\n- Task two'},
    {'project_id': 111, 'task_id': 333, 'spent_date': '2026-03-23', 'hours': 0.02, 'notes': ''},
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
OK|2026-03-23|Client Portal - API|0.02
OK|2026-03-23|Acme Corp [INT] Internal|0.02
FAIL|422|Project is archived
```

Capture the returned entry `id` from each successful POST — the next step writes them to the sidecar.

If any entry fails, report the error and continue with the rest.

## Step 6: Update tickets sidecar

After successful entry creation, update `~/daily_reports/meta/tickets.json` so per-ticket rollups are O(1) for downstream skills (`value-estimates`, future report skills).

Schema — keys are `{project_slug}#{ticket}`, where `project_slug` is the first `log_aliases` token of the matched project entry in `projects.yml` (so `ih#189`, not the long Harvest name):

```json
{
  "ih#189": {
    "title": "Update site search placeholder to 'Search Island Health'",
    "harvest_project": "Modernization of Island Health’s Digital Entry Point for Health Services | VIHA PO# 1401706",
    "first_seen": "2026-05-04",
    "last_seen": "2026-05-04",
    "days_active": 1,
    "harvest_hours": 0.02,
    "harvest_entry_ids": [2920326492]
  }
}
```

Upsert rules per ticket touched in this run:
- `title` — set on first sight to the cleaned `###` header of the first entry; never overwritten unless empty.
- `harvest_project` — the matched Harvest project name.
- `first_seen` / `last_seen` — min / max of all dates this ticket appears on (across the lifetime of the file, not just this run).
- `days_active` — count of distinct dates in the union of all dates this ticket has appeared on.
- `harvest_hours` — sum of `hours` from every linked Harvest entry id (re-derive from Harvest, do not just add this run's hours, so user-edited durations are reflected accurately).
- `harvest_entry_ids` — append-only set of Harvest entry IDs created for this ticket.

If the file doesn't exist, create it. Read → mutate in memory → write atomically (write to `tickets.json.tmp`, rename). The no-ticket bucket and the admin entry are **not** recorded in the sidecar.

The sidecar is also a natural surface for a future `--backsync` mode (see Roadmap) that pulls actual hours from Harvest and writes them back into the daily report markdown.

## Step 7: Report results

After all entries are created, show a final summary:
- How many entries were created
- Any that failed and why
- Any log entries that were skipped (excluded projects, no project match, etc.)

## Roadmap

Known follow-ups, not yet implemented:

- **`**Tickets:**` line backfill.** When the user supplies a ticket via the inline prompt in Step 3, write a `**Tickets:** #NNN` line back into the source markdown so the file becomes self-describing for next time. Out of scope until the parser side is proven.
- **`--backsync` mode.** Pull every Harvest entry for the past N days and write actual hours back into the matching daily report entry as a `**Hours:**` line, so the daily report mirrors Harvest at any point. Depends on per-ticket entries being stable (already true) and the sidecar (already in place).
- **Variance persistence.** Extend the sidecar (or add `~/daily_reports/meta/estimates.json`) so each ticket carries `{estimate_hours, estimate_source, actual_hours, variance, computed_at}` over time, giving longitudinal accuracy data instead of point-in-time snapshots.
