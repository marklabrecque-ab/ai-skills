---
name: next-due-retainer
description: "Find the next due retainer work item on Affinity Bridge's self-hosted GitLab (git.affinitybridge.com) under the 'Retainers and Maintenance' group, assign it to the user, and label it 'In Progress'. Use whenever the user asks for the next retainer to work on, says 'what retainer is next', 'pick up the next retainer', 'start the next retainer', or similar. Selection priority: issues already assigned to the user (earliest due_date wins), then unassigned open issues without the 'In Progress' label (earliest due_date wins). Excludes the 'mainwp' project. After picking, scans the three most recent comments and flags the issue for review if any comment was posted after the issue's due_date."
---

# next-due-retainer

Pick up the next retainer work item from the Affinity Bridge GitLab.

## Context

- **GitLab host**: `git.affinitybridge.com` (self-hosted). The `glab` CLI is already authenticated for this host.
- **Group**: `affinitybridge/retainers-and-maintenance` (group id `647`).
- **Projects in scope**: every project in the group **except** `mainwp` (project id `614` / path `affinitybridge/retainers-and-maintenance/mainwp`). Treat any new project that gets added to the group as in-scope automatically — only filter out `mainwp` by name/id.
- **User's GitLab username**: `mark`.

Always use `glab api` (not the GitLab MCP) — the self-hosted instance is what `glab` is configured against.

## Selection algorithm

1. **Fetch open issues** for the group, ordered by due date ascending:

   ```bash
   glab api "groups/647/issues?state=opened&order_by=due_date&sort=asc&per_page=100"
   ```

   Filter out:
   - Any issue whose `references.full` (or `project_id`) is the `mainwp` project.
   - Any issue with no `due_date` set (cannot rank it).

2. **Priority pass — already mine.** From the filtered list, pick the issue with the earliest `due_date` whose `assignees` includes `mark`. If found, that's the pick. (It's fine if it already has the `In Progress` label — just keep it.)

3. **Fallback pass — fair game.** Otherwise, pick the earliest-due issue that satisfies *both*:
   - `assignees` is empty, **and**
   - `labels` does **not** include `In Progress`.

4. If neither pass yields anything, report that to the user and stop. Do not modify any issue.

## After picking

Once an issue is chosen:

1. **Recent-comment review check.** Fetch the three most recent notes (comments) on the issue:

   ```bash
   glab api "projects/<project_id>/issues/<iid>/notes?sort=desc&order_by=created_at&per_page=3"
   ```

   Ignore system notes (`system: true`). For each remaining note, compare `created_at` to the issue's `due_date`. If **any** note's `created_at` is strictly after the `due_date`, flag the issue as **"needs review"** and include a direct link to that note (`<issue_web_url>#note_<note_id>`).

2. **Confirm with the user before any write.** Before mutating the issue, show the user:
   - Issue title, `web_url` (clickable for human verification), and `due_date`.
   - Which pass selected it ("already assigned to you" vs "unassigned + not In Progress").
   - The exact change(s) about to be made (e.g. "assign to `mark`, add label `In Progress`", or "no changes — already yours and In Progress").
   - The "needs review" flag and late-comment link(s), if any.

   Then ask the user to confirm. Do **not** call any `PUT` / `POST` endpoint until the user explicitly approves. If they decline or want a different issue, stop and wait — don't auto-pick the next candidate.

3. **Assign and label.** After confirmation, and only if there's something to change:

   ```bash
   glab api --method PUT "projects/<project_id>/issues/<iid>" \
     -f "assignee_ids=<mark_user_id>" \
     -f "add_labels=In Progress"
   ```

   To resolve `mark`'s numeric user id once: `glab api "users?username=mark"` → take `[0].id`. Cache it in memory for the run; don't hardcode.

   If the issue already carries the `In Progress` label, omit `add_labels` to avoid a no-op API noise. If it's already assigned to the user and already In Progress, skip the PUT entirely.

4. **Locate / clone the repo.** After the assignment has actually been made (or skipped because nothing needed changing), check the issue's `description` for a repository pointer:

   - Scan for a line matching (case-insensitive) `^\s*(Repo|Repository)\s*[:=]\s*(.+)$`, or a GitLab URL on a line/label that mentions "Repo" / "Repository". Extract either:
     - a project path like `affinitybridge/foo/bar`, or
     - a full URL like `https://git.affinitybridge.com/affinitybridge/foo/bar` (with or without `.git`), or
     - an SSH URL like `git@gitlab-ab:affinitybridge/foo/bar.git`.
   - Normalize to the **bare repo name** (the last path segment, minus `.git`). That's the directory name to look for under `~/Projects/`.

   If no repo indicator can be found, tell the user and stop — do **not** guess.

   Then:

   a. **Check `~/Projects/<repo-name>` for an exact directory-name match.**

      - If it exists *and* is a git repo (`<dir>/.git`), run `git -C ~/Projects/<repo-name> remote -v`. Compare each remote URL against the URL extracted from the ticket (normalize host: `git@gitlab-ab:owner/repo.git` ≡ `https://git.affinitybridge.com/owner/repo.git` ≡ `owner/repo`). If any remote matches, report which remote (usually `origin`) and confirm the local clone is correct. If none match, surface the mismatch to the user with both the ticket URL and the actual remotes — do not change remotes automatically.
      - If the directory exists but isn't a git repo, flag it and stop — don't touch it.

   b. **If `~/Projects/<repo-name>` does not exist**, clone the repo there using the `gitlab-ab` SSH host (the user's standard for AB GitLab):

      ```bash
      git clone git@gitlab-ab:<owner>/<repo>.git ~/Projects/<repo-name>
      ```

      Report the clone result (path + commit of `HEAD`). Don't `cd` into it or run anything else inside.

5. **Report.** Output to the user:
   - The issue title and `web_url`.
   - Due date.
   - Whether you assigned it / added the label, or whether it was already yours.
   - If flagged as **needs review**, a clearly visible note with the link(s) to the late comment(s) and a one-line summary of what those comments say.
   - Repo status: located at `~/Projects/<repo-name>` (remote OK / remote mismatch), or freshly cloned, or no repo indicator found in the description.

## Notes / edge cases

- `glab` returns paginated results — 100 per page is enough for this group today, but if the open-issue count grows past that, paginate with `--paginate` or `page=N`.
- If `glab api` fails with auth errors, surface the error directly. Don't try to re-auth on the user's behalf.
- Don't change the due date, milestone, or any other field. Only `assignee_ids` and `add_labels`.
- The "In Progress" label must match exactly (case-sensitive on GitLab). Confirm spelling from a known issue's label list if uncertain.
