---
name: wordpress-update-check
description: Audits pending WordPress plugin updates and produces a per-plugin risk report based on actual code diffs between the installed and incoming versions. Use whenever the user runs /wordpress-update-check, asks to "check WordPress updates", "review plugin updates before applying", "see what's changing in pending plugin updates", or wants a pre-flight risk assessment before running wp plugin update. Works in any WordPress project that uses DDEV and has wp-cli available.
---

# WordPress Update Check

Produces a markdown risk report covering every pending WordPress plugin update on the site, by fetching the incoming version's source code and diffing it against the currently installed code. Risk is inferred from what the diff actually contains — not from semver, which WordPress plugins do not follow reliably.

## When to use

- The user runs `/wordpress-update-check` (with optional plugin slugs to narrow scope: `/wordpress-update-check wordpress-seo mailpoet`)
- The user wants to know what will change before applying plugin updates
- The user is preparing a maintenance window and needs to flag risky updates

## Assumptions

- The project is a WordPress site rooted at the current working directory (look for `wp-config.php`, or `web/wp-config.php` / `public_html/wp-config.php`).
- DDEV is configured (`.ddev/config.yaml` exists).
- `ddev wp ...` works (wp-cli inside the web container).
- The site is running. If `ddev status` shows web stopped, prompt the user to start it before continuing.

## Output

- **Report**: `docs/wordpress-update-check-YYYY-MM-DD.md` (overwrite if a same-day run already exists, after a one-line confirmation)
- **Working files**: `scratch/wordpress-update-check/<run-id>/` — fetched zips, extracted trees, raw diffs. Gitignored. Keep these around so the user can dig deeper after reading the report.
- **Terminal**: a short summary table at the end (plugin, current → new, risk, link to its section in the report), followed by two wp-cli command suggestions.

## Workflow

### Step 1 — Discover pending updates

```bash
ddev wp plugin list --update=available --fields=name,version,update_version,update_package,status --format=json
```

If the user passed plugin slugs as arguments, filter the result to those slugs (warn and skip any slug that has no pending update). If the result is empty, tell the user there's nothing to check and stop.

Create the run dir: `scratch/wordpress-update-check/<UTC-timestamp>/`. Use this for all intermediate files.

### Step 2 — Classify each plugin: wp.org vs premium

Look at the `update_package` URL:

- **wp.org-hosted** — URL is on `downloads.wordpress.org`. We can fetch both the installed version (`https://downloads.wordpress.org/plugin/<slug>.<current>.zip`) and the new version (`https://downloads.wordpress.org/plugin/<slug>.<new>.zip`) freely.
- **Premium / vendor-hosted** — anything else (S3 signed URLs, vendor download servers, etc.). These typically require a license and the signed URL expires.

For premium plugins:
1. Pass the vendor URL to the helper via `--new-url "<url>"` along with `--use-installed-as-old` — the helper will fetch the new version from that URL instead of wp.org and use the installed plugin dir as the old tree.
2. If the download fails (403, 404, expired signature, etc.), mark it **skipped** with the reason. Note it in the summary and report.

### Step 3 — Fetch and diff

Use the bundled helper:

```bash
scripts/fetch_and_diff.sh <slug> <current-version> <new-version> <run-dir>
```

This downloads both versions (when available on wp.org) into `<run-dir>/<slug>/old/` and `<run-dir>/<slug>/new/`, then writes:

- `<run-dir>/<slug>/diff.patch` — unified diff (output of `diff -urN`)
- `<run-dir>/<slug>/changed-files.txt` — list of changed paths with status (A/M/D)
- `<run-dir>/<slug>/changelog.txt` — extracted "== Changelog ==" section from the new version's `readme.txt`, when present

If the new version can't be fetched, the script exits non-zero with a reason — record it as skipped.

For premium plugins where the vendor URL is still valid, pass both `--new-url "<vendor-url>"` and `--use-installed-as-old`:

```bash
scripts/fetch_and_diff.sh <slug> <current> <new> <run-dir> \
  --use-installed-as-old --new-url "<vendor-signed-url>"
```

The script will fetch the new version from the vendor URL and diff against `wp-content/plugins/<slug>/` on disk.

Run fetches in parallel where reasonable — kick off all plugins together with `&`, then `wait`. The helper is self-contained, no shared state.

### Step 4 — Analyze each diff

This is the heart of the skill. For every non-skipped plugin, read the diff and changelog and infer risk. You are not following a checklist — you are reading the code like a reviewer.

Signals that typically matter (non-exhaustive, use judgment):

- **Removed or renamed public symbols** — functions, classes, methods, hooks (`do_action`, `apply_filters`), shortcodes, REST routes, CLI commands. If a hook is gone, grep the site for it (see Step 5).
- **Changed function signatures** — added required params, reordered params, changed return types.
- **File removals or renames** — themes and other plugins sometimes override or include specific plugin files directly.
- **Bumped requirements** — `Requires PHP` / `Requires at least` / `Tested up to` in the plugin header or `readme.txt`. Compare against the site's PHP and WP versions.
- **DB schema changes** — new `dbDelta` calls, `CREATE TABLE`, `ALTER TABLE`, new option keys, changed serialized formats. These usually run a migration on activation/update and can be hard to roll back.
- **Capability or role changes** — `add_cap`, `remove_cap`, new custom capabilities.
- **Security-flavoured changelog entries** — "fix", "security", "CVE", "XSS", "SQLi", "auth bypass". These can be reassuring (vendor is patching) or alarming (depending on whether breaking changes accompany the fix).
- **Major refactors** — large net-negative or net-positive line counts, mass file moves, namespace introductions, new dependencies in `composer.json` / `package.json`.
- **Bundled library updates** — `vendor/` or `node_modules/` style directories changing wholesale; usually low risk but worth noting if you see a major version bump.

Things to ignore or downweight:
- Pure translation file updates (`languages/*.po`, `*.mo`)
- Whitespace, comment, or docblock-only changes
- Built/minified asset churn that mirrors a source change you've already counted

### Step 5 — Cross-reference removed hooks against site code

For each removed `do_action` / `apply_filters` name you find, grep the site:

```bash
grep -RIn --include='*.php' "<hook_name>" wp-content/themes wp-content/mu-plugins wp-content/plugins 2>/dev/null \
  | grep -v "wp-content/plugins/<the-plugin-being-checked>/"
```

A hit means the site is actively listening to a hook that's about to disappear — that's a high-impact finding, call it out specifically with the file path and line.

Also worth grepping: removed functions/classes (with their fully qualified names), removed shortcodes, removed REST routes.

### Step 6 — Assign a risk rating

For each plugin, settle on **low**, **medium**, or **high**. This is your judgment call, but rough guidance:

- **Low** — translations only, bundled-library bumps, internal refactors with no public surface change, pure bug fixes with small diffs.
- **Medium** — meaningful code changes with no obvious cross-references in the site, requirement bumps the site already satisfies, schema additions (vs. destructive changes), new features that don't touch existing behaviour.
- **High** — removed/renamed public symbols that the site actually uses, destructive schema changes, requirement bumps the site doesn't satisfy, signature changes on functions the site calls, major rewrites.

If a plugin is skipped, its rating is **skipped (manual review required)**.

### Step 7 — Write the report

Path: `docs/wordpress-update-check-YYYY-MM-DD.md`. If `docs/` doesn't exist, create it. If today's report already exists, ask before overwriting.

Use this exact structure:

```markdown
# WordPress update check — YYYY-MM-DD

Site: <project-root-name>
Updates pending: <N>   Reviewed: <N>   Skipped: <N>

## Summary

| Plugin | Current → New | Risk | Notes |
|---|---|---|---|
| wordpress-seo | 27.4 → 27.5 | low | minor bugfixes, no public API changes |
| mailpoet | 5.23.2 → 5.25.0 | medium | new DB column on `mailpoet_subscribers`; safe additive |
| gravityforms | 2.10.0 → 2.10.1 | skipped | premium, vendor URL not accessible |

## Suggested commands

Apply only the low- and medium-risk updates:
\`\`\`
ddev wp plugin update <slug-a> <slug-b> ...
\`\`\`

Apply all non-skipped updates (review the report first):
\`\`\`
ddev wp plugin update <slug-a> <slug-b> <slug-c> ...
\`\`\`

## <plugin-slug> (current → new) — <risk>

**Changelog** (from readme.txt, if available):
> ...short excerpt...

**Highlights from the diff**:
- ... bulleted findings, with code references like `inc/foo.php:142` ...

**Cross-references in site code**:
- (or "None found.")

**Recommendation**: <one or two sentences>

---
(repeat per plugin)

## Skipped plugins

- **gravityforms** — premium, S3 signed URL was inaccessible (HTTP 403). Review the vendor's release notes manually before updating.
```

Per-plugin sections should be terse but specific. Cite file paths and line numbers from the diff wherever possible. Don't bury the finding in prose — bullet it.

### Step 8 — Print the terminal summary

After writing the report, echo the summary table and the two suggested wp-cli commands to the terminal. Include the path to the full report. Keep it short — the report has the detail.

Example:

```
Wrote docs/wordpress-update-check-2026-05-11.md

Plugin                Current → New        Risk
--------------------  -------------------  -------
wordpress-seo         27.4 → 27.5          low
mailpoet              5.23.2 → 5.25.0      medium
wp-store-locator      2.3.0 → 2.3.1        low
all-in-one-wp...      5.4.6 → 5.4.7        low
gravityforms          2.10.0 → 2.10.1      skipped

Suggested commands:
  ddev wp plugin update wordpress-seo mailpoet wp-store-locator all-in-one-wp-security-and-firewall
  ddev wp plugin update wordpress-seo mailpoet wp-store-locator all-in-one-wp-security-and-firewall
```

(If the low/medium and "all non-skipped" lists are identical, say so and only print one command.)

## Why this design

- **Diff-based, not semver-based.** WordPress plugins don't follow semver consistently. A 1.2.3 → 1.2.4 patch release can rip out a hook, and a 5.x → 6.x bump can be pure refactor. The diff is the ground truth.
- **Cross-referencing matters.** A removed hook in a plugin is meaningless if nothing on the site listens to it. The skill's value is connecting "what changed in the dependency" to "what the site relies on."
- **Premium plugins are second-class on purpose.** Trying to scrape vendor download servers or store license keys is brittle and a security risk. Surfacing the gap clearly ("skipped, review manually") is more honest than pretending to analyse what you can't see.
- **Report-only.** Applying updates is destructive (DB migrations, file overwrites). The skill produces information; the user runs the wp-cli command when they're ready.
