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
- **User's GitLab username**: resolved at runtime, not hardcoded. See *Resolving the current user* below.

Always use `glab api` (not the GitLab MCP) — the self-hosted instance is what `glab` is configured against.

## Resolving the clone directory

Where local clones live is configurable so teammates can keep their own filesystem layout.

- Read env var **`NEXT_DUE_RETAINER_CLONE_DIR`**.
- If set, expand `~` / `$HOME` and use that path as the base directory for all repo checks and clones below.
- If unset, default to **`~/Projects/retainers`**.

Cache the resolved path for the run. Throughout the rest of this skill, `<clone-dir>` refers to this resolved base.

The plugin is shared across the team, so the "me" username and user id must be discovered per-run rather than baked in. Resolve in this order and stop at the first hit:

1. **Env var `NEXT_DUE_RETAINER_USER`** — if set, treat its value as the GitLab username. Useful when a teammate is authed as one user but wants to filter as another, or for testing.
2. **`glab api user`** — returns the currently authenticated user. Take `.username` and `.id` directly from the response; no second lookup needed.

Cache the resolved `{username, id}` in memory for the run. Refer to "the user" throughout the rest of this skill — never assume `mark`.

If neither resolution works (no env var, `glab api user` fails), surface the error and stop.

## Selection algorithm

1. **Fetch open issues** for the group, ordered by due date ascending:

   ```bash
   glab api "groups/647/issues?state=opened&order_by=due_date&sort=asc&per_page=100"
   ```

   Filter out:
   - Any issue whose `references.full` (or `project_id`) is the `mainwp` project.
   - Any issue with no `due_date` set (cannot rank it).

2. **Priority pass — already mine.** From the filtered list, pick the issue with the earliest `due_date` whose `assignees` includes the resolved current-user username (see *Resolving the current user*). If found, that's the pick. (It's fine if it already has the `In Progress` label — just keep it.)

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
   - The exact change(s) about to be made (e.g. "assign to `<resolved-username>`, add label `In Progress`", or "no changes — already yours and In Progress").
   - The "needs review" flag and late-comment link(s), if any.

   Then ask the user to confirm. Do **not** call any `PUT` / `POST` endpoint until the user explicitly approves. If they decline or want a different issue, stop and wait — don't auto-pick the next candidate.

3. **Assign and label.** After confirmation, and only if there's something to change:

   ```bash
   glab api --method PUT "projects/<project_id>/issues/<iid>" \
     -f "assignee_ids=<resolved_user_id>" \
     -f "add_labels=In Progress"
   ```

   `<resolved_user_id>` comes from the cached resolution in *Resolving the current user* (the `.id` from `glab api user`, or — if the env var override was used — `glab api "users?username=<env-value>"` then `[0].id`). Don't hardcode any user id.

   If the issue already carries the `In Progress` label, omit `add_labels` to avoid a no-op API noise. If it's already assigned to the user and already In Progress, skip the PUT entirely.

4. **Locate / clone the repo.** After the assignment has actually been made (or skipped because nothing needed changing), check the issue's `description` for a repository pointer:

   - Scan for a line matching (case-insensitive) `^\s*(Repo|Repository)\s*[:=]\s*(.+)$`, or a GitLab URL on a line/label that mentions "Repo" / "Repository". Extract either:
     - a project path like `affinitybridge/foo/bar`, or
     - a full URL like `https://git.affinitybridge.com/affinitybridge/foo/bar` (with or without `.git`), or
     - an SSH URL like `git@gitlab-ab:affinitybridge/foo/bar.git`.
   - Normalize to the **bare repo name** (the last path segment, minus `.git`). That's the directory name to look for under `<clone-dir>/`.

   If no repo indicator can be found, tell the user and stop — do **not** guess.

   Then:

   a. **Check `<clone-dir>/<repo-name>` for an exact directory-name match.**

      - If it exists *and* is a git repo (`<dir>/.git`), run `git -C <clone-dir>/<repo-name> remote -v`. Compare each remote URL against the URL extracted from the ticket (normalize host: `git@gitlab-ab:owner/repo.git` ≡ `https://git.affinitybridge.com/owner/repo.git` ≡ `owner/repo`). If any remote matches, report which remote (usually `origin`) and confirm the local clone is correct. If none match, surface the mismatch to the user with both the ticket URL and the actual remotes — do not change remotes automatically.
      - If the directory exists but isn't a git repo, flag it and stop — don't touch it.

   b. **If `<clone-dir>/<repo-name>` does not exist**, clone the repo there using the `gitlab-ab` SSH host (the user's standard for AB GitLab):

      ```bash
      git clone git@gitlab-ab:<owner>/<repo>.git <clone-dir>/<repo-name>
      ```

      Report the clone result (path + commit of `HEAD`).

5. **Prepare the working branch and boot DDEV.** Once a repo has been located *or* freshly cloned in step 4, set up the working environment. All commands run with `<clone-dir>/<repo-name>` as the working directory — use `git -C` and `cd` explicitly rather than relying on ambient state.

   a. **Switch to `main` and update it.**

      ```bash
      cd <clone-dir>/<repo-name>
      git checkout main
      git pull --ff-only origin main
      ```

      If `git checkout main` fails because of dirty working state, stop and surface the error to the user — don't `stash`, `reset`, or `--force` anything. If the repo's default branch isn't `main` (e.g. `master`, `develop`), tell the user and stop.

      If `git pull --ff-only` fails (e.g. local `main` has diverged), surface the error — don't attempt a rebase or merge.

   b. **Create the working branch.**

      ```bash
      git checkout -b retainer-update
      ```

      If a `retainer-update` branch already exists locally, do **not** delete or overwrite it. Instead, surface the situation to the user and ask whether to switch to the existing branch, pick a different name, or stop. Don't proceed silently.

   c. **Start DDEV and pull prod.**

      ```bash
      ddev start
      ddev pull prod
      ```

      - If the repo has no `.ddev/` directory, skip this step and note it in the report — not every retainer is a DDEV project.
      - If `ddev pull prod` fails because no `prod` provider is configured, surface the error and suggest the [`ddev-setup`](../../../ddev-setup) skill, but don't invoke it automatically.
      - Stream output so the user can see progress; these commands can take a while.

6. **Final report.** Always print an end-of-run summary, even if the skill stopped partway through (declined confirmation, missing repo indicator, dirty branch, DDEV failure, etc.). The report should let the user see at a glance everything the skill did and everything it couldn't do. Use this structure:

   ```markdown
   ## Next-due retainer — run summary

   **Ticket:** [<title>](<web_url>)
   **Due:** <YYYY-MM-DD>
   **Selected via:** already assigned to <user> | unassigned & not In Progress
   **Needs review:** yes (late comments listed below) | no

   ### Steps

   - ✅ / ⚠️ / ❌  <step name> — <one-line outcome>
   - …

   ### Problems

   - <problem 1, with the specific error message or link>
   - …
   (omit this section entirely if there were none)

   ### Next steps for the user

   - <e.g. "review the late comment at <url> before starting work">
   - <e.g. "resolve dirty working tree in <path>, then re-run">
   ```

   Cover, in order, with a status icon for each (✅ done, ⚠️ done with caveats, ❌ not done / failed / skipped):

   1. **Resolved user** — username + id source (`glab api user` vs `NEXT_DUE_RETAINER_USER` override).
   2. **Resolved clone dir** — path + whether from default or `NEXT_DUE_RETAINER_CLONE_DIR`.
   3. **Issue selection** — which selection pass matched, and how many candidates were considered.
   4. **Recent-comment review check** — note any late comments with direct links (`<web_url>#note_<id>`).
   5. **User confirmation** — confirmed / declined.
   6. **GitLab write** — assignment + label change (or noted as already in that state, or skipped because the user declined).
   7. **Repo discovery** — what was extracted from the description (or that no `Repo:`/`Repository:` line was found).
   8. **Local repo** — located (remote OK / remote mismatch with details) or freshly cloned (with `HEAD` short SHA).
   9. **Branch prep** — `main` updated + `retainer-update` created (or whatever happened instead).
   10. **DDEV** — `ddev start` and `ddev pull prod` outcomes, or skipped because no `.ddev/`.

   The **Problems** section should re-surface anything from the steps above that has a ⚠️ or ❌ icon — copying the salient error text so the user doesn't have to scroll back through `ddev` / `git` output. If a step short-circuited the run, say so explicitly ("stopped here — no further steps attempted").

   The **Next steps** section is optional; only include actionable items the user needs to take themselves (re-auth, fix a remote, resolve a conflict, set an env var, install a missing tool, etc.). Don't pad with generic advice.

## Notes / edge cases

- `glab` returns paginated results — 100 per page is enough for this group today, but if the open-issue count grows past that, paginate with `--paginate` or `page=N`.
- If `glab api` fails with auth errors, surface the error directly. Don't try to re-auth on the user's behalf.
- Don't change the due date, milestone, or any other field. Only `assignee_ids` and `add_labels`.
- The "In Progress" label must match exactly (case-sensitive on GitLab). Confirm spelling from a known issue's label list if uncertain.
