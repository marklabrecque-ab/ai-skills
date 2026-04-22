---
name: screenshot-skill-init
description: >
  Generator skill. Produces a pair of project-specific screenshot + compare
  skills committed to the current project's .claude/skills/ directory, so any
  collaborator who pulls the repo can run them. Use when the user wants to set
  up visual regression screenshots for a new project, asks to "generalize the
  screenshot skill" into a new repo, or says something like "init screenshot
  skills here", "scaffold screenshot testing", or "add the leaf-style
  screenshot skills to this project". Detects WordPress/Drupal/DDEV, discovers
  primary-nav pages via wp-cli or drush, and supports auth'd staging targets.
---

# Screenshot Skill Generator

Generates two project-specific skills into `<project>/.claude/skills/`:

- `screenshot-<slug>/` — captures full-page screenshots of a curated list of
  pages across one or more targets (ddev, production, staging, etc.)
- `compare-<slug>-screenshots/` — diffs two screenshot runs, fast size/dim
  pass then visual inspection on flagged pages

Both generated skills share a single `pages.json` so the page list is never
duplicated (fixes the duplication bug in the original LEAF skills).

## Prerequisites

- The current working directory is a project repo (has a `.git` dir or similar)
- `python3` available (used by the renderer and the generated scripts)
- For WP menu discovery: DDEV + `wp-cli` installed in the web container
- For Drupal menu discovery: DDEV + `drush`

## Step-by-step

### Step 1 — Confirm project context

Read the current working directory. Propose `<slug>` as the lowercased
basename (e.g. `/Users/mark/Projects/leaf` → `leaf`). Ask the user to confirm
or override. Ensure `.claude/skills/` exists; create it if not.

### Step 2 — Detect stack

Check for these markers (in order, first match wins):

| Stack | Markers |
|-------|---------|
| WordPress | `wp-config.php`, `public_html/wp-config.php`, `web/wp-config.php` |
| Drupal | `web/core/`, `docroot/core/`, or `drupal/core` in `composer.json` |
| Generic | none of the above |

Independently, check for `.ddev/config.yaml` to know whether DDEV is available.

### Step 3 — Gather targets

Ask the user which targets to configure. Typical set:

- **ddev** — `https://<slug>.ddev.site` (self-signed cert; set `self_signed: true`)
- **production** — ask user for the URL
- **staging** (optional) — ask for URL and whether HTTP basic auth is needed

For auth'd targets, DO NOT collect credentials directly. Instead, record
**env var names** (e.g. `STAGING_AUTH_USER`, `STAGING_AUTH_PASS`) that the
generated script will read at runtime. The user puts actual creds in their
shell or a `.env` file that is `.gitignore`d.

Targets are recorded as a list like:

```json
[
  {"name": "ddev", "url": "https://leaf.ddev.site", "self_signed": true},
  {"name": "production", "url": "https://www.leaf.ca"},
  {"name": "staging", "url": "https://stage.example.com", "auth_user_env": "STAGING_AUTH_USER", "auth_pass_env": "STAGING_AUTH_PASS"}
]
```

### Step 4 — Discover pages

Offer the user these discovery methods via AskUserQuestion:

- **WP + DDEV** → run `scripts/discover_wp.sh` (requires `ddev` running)
- **Drupal + DDEV** → run `scripts/discover_drupal.sh`
- **Manual paste** → show a template and let the user paste `name,path` lines

Each method produces a list of `{name, path}` objects. Names follow the
`NN-slug` convention (e.g. `00-home`, `01-about`) so the sorted file order
matches the intended reading order.

After discovery, show the list to the user and let them prune/reorder before
writing. This human-in-the-loop step is critical — menus usually contain
cruft.

### Step 5 — Render templates

Use the bundled renderer:

```bash
python3 ~/skills/screenshot-skill-init/scripts/render.py \
  --slug <slug> \
  --project-name "<Project Name>" \
  --targets <targets.json> \
  --pages <pages.json> \
  --out <project>/.claude/skills/
```

The renderer:
- Writes `screenshot-<slug>/SKILL.md`, `screenshot-<slug>/scripts/screenshot.py`, `screenshot-<slug>/pages.json`
- Writes `compare-<slug>-screenshots/SKILL.md`, `compare-<slug>-screenshots/scripts/compare.py`
- Substitutes `{{SLUG}}`, `{{PROJECT_NAME}}`, `{{TARGETS_JSON}}` inline
- Copies `pages.json` verbatim (single source of truth)

### Step 6 — Verify

```bash
python3 <project>/.claude/skills/screenshot-<slug>/scripts/screenshot.py --help
python3 <project>/.claude/skills/compare-<slug>-screenshots/scripts/compare.py --help
```

Both should print usage cleanly. Offer a smoke test: capture the homepage only
against the first non-auth target using `--only 00-home` (or similar, if
implemented — otherwise just run the full screenshot against ddev).

### Step 7 — Report back

Summarize what was written:
- New skill dirs and files
- Which discovery method was used
- Any env vars the user needs to set for auth'd targets

**Do not auto-commit** — surface the new files via `git status` and let the
user commit per their project's conventions.

## Notes

- The renderer is deliberately simple string substitution — no Jinja/mustache
  dependency. If templating grows, revisit.
- The generated scripts use `uv run --with playwright` as the recommended
  invocation (matches the LEAF convention), but fall back to plain `python3`
  if `playwright` is already installed.
- Regenerating: re-running this skill in a project overwrites the previous
  generation. Warn the user and diff before accepting if they have local
  modifications to the generated skills.
