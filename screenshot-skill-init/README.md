# screenshot-skill-init

Generator skill that scaffolds a pair of project-specific Claude Code skills into a repo's `.claude/skills/` directory:

- **`screenshot-<slug>/`** — captures full-page PNG screenshots of a curated page list across one or more targets (ddev, production, staging, etc.)
- **`compare-<slug>-screenshots/`** — diffs two screenshot runs (fast size/dimension pass, then visual inspection on flagged pages)

Both generated skills share a single `pages.json` as the source of truth for the page list.

Credit: the generated skills are based on the original LEAF skills authored by Dale McGladdery.

## Usage

From inside a project repo:

```
/screenshot-skill-init
```

The skill detects WordPress/Drupal/DDEV, discovers primary-nav pages (via `wp-cli` or `drush`), prompts you to prune the list, then writes the two skills into `.claude/skills/`. Commit them so collaborators who pull the repo can run the skills directly.

See `skills/screenshot-skill-init/SKILL.md` for the full step-by-step the skill follows.

## What gets generated

```
<project>/.claude/skills/
├── screenshot-<slug>/
│   ├── SKILL.md
│   ├── pages.json              ← edit to add/remove/reorder pages
│   └── scripts/
│       └── screenshot.py       ← edit TARGETS at top to change base URLs
└── compare-<slug>-screenshots/
    ├── SKILL.md
    └── scripts/
        └── compare.py
```

## Adding or removing pages later

Edit **`.claude/skills/screenshot-<slug>/pages.json`** directly. It's a plain JSON list of `[name, path]` pairs (paths relative to each target's base URL). Both the screenshot and compare skills read from this file — no duplication.

Naming convention: `NN-slug` (e.g. `00-home`, `01-about`) so sorted file order matches intended reading order.

## Changing or adding targets

Edit the `TARGETS` constant at the top of **`.claude/skills/screenshot-<slug>/scripts/screenshot.py`**.

Each target is an object like:

```json
{"name": "ddev",       "url": "https://leaf.ddev.site", "self_signed": true}
{"name": "production", "url": "https://www.leaf.ca"}
{"name": "staging",    "url": "https://stage.example.com",
                       "auth_user_env": "STAGING_AUTH_USER",
                       "auth_pass_env": "STAGING_AUTH_PASS"}
```

For auth'd targets, store credentials in your shell or a gitignored `.env` — never commit them. The script reads the env vars named in `auth_user_env` / `auth_pass_env` at runtime.

## Regenerating

Re-running `/screenshot-skill-init` in the same project overwrites the previously generated skills. If you've made local edits (notably to `pages.json`), back them up or diff before accepting.

## Prerequisites

- Project is a git repo
- `python3` available
- For WordPress page discovery: DDEV + `wp-cli` in the web container
- For Drupal page discovery: DDEV + `drush`
- Playwright (the generated scripts invoke it via `uv run --with playwright` by default)
