---
name: ddev-setup
description: Sets up a functional DDEV environment for a Drupal or WordPress project. Creates DDEV provider YAML files (.ddev/providers/*.yaml) for `ddev pull`, wires `ddev auth ssh` into post-start, and for WordPress projects bootstraps a committed `wp-config-local.php` + `wp-config-override.php` pair so fresh clones boot cleanly and `$table_prefix` (or similar) can be overridden last-in-cascade. Use when the user wants to set up `ddev pull`, add a new environment (prod/stage/dev/cert) to a DDEV project, configure database and files sync from a remote server, fix a missing or broken provider, bootstrap a WordPress wp-config for a fresh clone, or mentions needing a "DDEV provider" or "DDEV setup". The skill detects the project's CMS (Drupal vs WordPress) from the codebase and selects the correct templates.
---

# DDEV Setup

Bring a Drupal or WordPress project to a functional DDEV state. Two concerns:

1. **Provider file** — `.ddev/providers/<name>.yaml` so `ddev pull <name>` can sync a database and user-uploaded files from a remote server.
2. **WordPress wp-config bootstrap** (WordPress only) — commit a `wp-config-local.php` that DDEV copies into `wp-config.php` on first start if it's missing, plus a `wp-config-override.php` that's included last in the config cascade so per-project overrides (notably `$table_prefix`) win.

Templates live in `templates/` alongside this file.

## When to use

- The user asks to set up `ddev pull` on a project
- The user wants to add a new environment (e.g. `prod`, `stage`, `dev`, `cert`) to an existing DDEV project
- The user says the provider is missing or broken
- The user is being walked through by `affinity-clone` and the script reports "No DDEV provider found"

## Step 1 — Detect the CMS

From the project root, pick the matching template:

| Signal | CMS | Template |
|---|---|---|
| `composer.json` contains `"drupal/core"` or `"drupal/recommended-project"` | Drupal | `templates/drupal.yaml` |
| `wp-config.php` at the project root, or `composer.json` contains `"johnpbloch/wordpress"` | WordPress | `templates/wordpress.yaml` |
| Both or neither | Ask the user | — |

Don't guess. If the signals conflict (rare, e.g. a composite site), ask which one this provider is for.

## Step 2 — Gather the connection details

Ask the user for what you don't already know. Reasonable things to offer defaults for:

| Value | Default / Hint |
|---|---|
| Environment name (file name) | `prod`, `stage`, `dev`, `cert` — ask which |
| SSH user | — (always ask) |
| SSH host | — (always ask; may be an IP, FQDN, or an `~/.ssh/config` alias) |
| SSH port | `22` |
| Remote path | — (always ask; the composer/project root on the server) |
| Backup path | Same as Remote path — don't prompt. The dump is written there, rsynced, then removed. |

**Drupal-specific:**
- `FILES_SUBPATH` — default `web/sites/default/files`. Change if the project uses a different docroot (e.g. `docroot/sites/default/files`, or `sites/default/files` for non-composer sites).

If the user only has an `~/.ssh/config` alias (e.g. `islandhealth-prod`) and no separate user/port/keyfile, warn them: `affinity-clone` requires both a `*HOST*` and a `*USER*` env var in the provider file. Either resolve the alias (`ssh -G <alias> | grep -E '^(user|hostname|port|identityfile)'`) and fill the fields, or leave it — but `affinity-clone`'s preflight parser will refuse the file.

## Step 3 — Write the file

1. **Check if the target file already exists.** If `<project-root>/.ddev/providers/<environment-name>.yaml` exists, **STOP**. Do not overwrite it under any circumstances — it may contain hand-tuned settings (custom backup paths, `stage_file_proxy` no-ops, SSH-alias forms) that the template cannot reproduce. This rule is absolute for `prod.yaml` in particular: production providers are the highest-risk to clobber. Report the existing file to the user, show its contents, and ask whether they want to (a) leave it alone, (b) edit specific fields in place, or (c) explicitly confirm a full rewrite by deleting the file themselves first. Never use `Write` to replace it.
2. Read the matching template. Templates are located at `~/.claude/skills/ddev-setup/templates/` (resolve `~` to the user's home directory for an absolute path).
3. Replace every `{{PLACEHOLDER}}` token with the gathered value.
4. Write the result to `<project-root>/.ddev/providers/<environment-name>.yaml`.
5. Do NOT include the DDEV-generated sentinel comment (`#ddev-generated`) — that comment signals DDEV can overwrite the file. Custom providers must omit it.

Verify: grep the output for any remaining `{{` — if any, you missed a placeholder.

## Step 4 — Wire `ddev auth ssh` into `post-start`

Edit `.ddev/config.yaml` so SSH keys are loaded into `ddev-ssh-agent` automatically after every `ddev start`, removing the need to run `ddev auth ssh` manually before each pull.

Desired entry:

```yaml
hooks:
  post-start:
    - exec-host: ddev auth ssh
```

Merge carefully:

- If `hooks:` and `post-start:` already exist, append `- exec-host: ddev auth ssh` to the existing list (don't replace).
- If `hooks:` exists but has no `post-start:`, add the `post-start:` key with this one entry.
- If `hooks:` doesn't exist, append the block above.
- If the entry is already present, skip.

## Step 4b — WordPress only: disable `upload_dirs` handling

The WordPress template's `files_import_command` runs on the host and rsyncs into `wp-content/uploads/` on the host filesystem. This only works if DDEV isn't applying its default `upload_dirs` behaviour (which shoves that path into a docker volume that's invisible from the host, breaking `rsync --size-only` across pulls).

In `.ddev/config.yaml`, add or set:

```yaml
upload_dirs: []
```

If `upload_dirs` is already present with a non-empty list, replace it with `[]` and ask the user to confirm — they may have set it deliberately for a non-standard uploads path, in which case the template's dest path needs adjusting to match.

## Step 4c — WordPress only: domain swap on `post-import-db`

After `ddev pull <env>`, the imported database still references the production domain everywhere — internal links, image src, Elementor's serialized layout data. Without a search-replace step, the local site loads but every click sends the user back to production. Wire this into `.ddev/config.yaml` as a `post-import-db` hook so it runs automatically after every pull.

Ask the user for:

- The production domain(s) — both `www.` and bare forms if both resolve (e.g. `www.example.ca` and `example.ca`)
- The local DDEV domain — usually `<project-name>.ddev.site` (read `name:` from `.ddev/config.yaml`)
- Whether the site uses Elementor (check `wp-content/plugins/elementor*`)

Desired entry (adapt domains; drop the Elementor lines if not applicable):

```yaml
hooks:
  post-import-db:
    # Canonicalize http:// to https:// first so the domain swap below can't
    # reintroduce mixed content. Two forms: plain (PHP-serialized data) and
    # JSON-escaped slashes (Elementor stores content as JSON).
    - exec: wp search-replace 'http://www.{{PROD_DOMAIN}}' 'https://www.{{PROD_DOMAIN}}' --all-tables --skip-columns=guid
    - exec: wp search-replace 'http://{{PROD_DOMAIN}}' 'https://{{PROD_DOMAIN}}' --all-tables --skip-columns=guid
    - exec: wp search-replace 'http:\/\/www.{{PROD_DOMAIN}}' 'https:\/\/www.{{PROD_DOMAIN}}' --all-tables --skip-columns=guid
    - exec: wp search-replace 'http:\/\/{{PROD_DOMAIN}}' 'https:\/\/{{PROD_DOMAIN}}' --all-tables --skip-columns=guid
    # Domain swap — www first so its matches aren't swallowed by the bare-domain pass.
    - exec: wp search-replace '://www.{{PROD_DOMAIN}}' '://{{LOCAL_DOMAIN}}' --all-tables --skip-columns=guid
    - exec: wp search-replace '://{{PROD_DOMAIN}}' '://{{LOCAL_DOMAIN}}' --all-tables --skip-columns=guid
    - exec: wp search-replace ':\/\/www.{{PROD_DOMAIN}}' ':\/\/{{LOCAL_DOMAIN}}' --all-tables --skip-columns=guid
    - exec: wp search-replace ':\/\/{{PROD_DOMAIN}}' ':\/\/{{LOCAL_DOMAIN}}' --all-tables --skip-columns=guid
    # Elementor: only include if the site uses Elementor.
    - exec: wp elementor replace-urls https://{{PROD_DOMAIN}} https://{{LOCAL_DOMAIN}}
    - exec: wp elementor replace-urls https://www.{{PROD_DOMAIN}} https://{{LOCAL_DOMAIN}}
    - exec: wp elementor flush-css
    - exec: wp cache flush
```

Why each piece matters:

- **Canonicalize `http://` → `https://` first.** If you swap domains before normalizing the scheme, you'll end up with mixed content — local on `https`, but some old `http://prod.example.ca` rows now point to `http://local.ddev.site`.
- **Both plain and JSON-escaped-slashes forms.** WordPress's standard search-replace hits PHP-serialized data fine, but Elementor stores layouts as JSON, where `/` is escaped to `\/`. The escaped-slash variants catch those rows.
- **`www` before bare domain.** `wp search-replace '://example.ca' ...` matches `://www.example.ca` too — if you run the bare-domain pass first, the `www.` prefix gets orphaned. Always do `www` first.
- **`--skip-columns=guid`.** Canonical WordPress advice: GUIDs are permanent identifiers, never URLs to follow. Rewriting them confuses feed readers.
- **Elementor `replace-urls` + `flush-css`.** Elementor caches generated CSS files keyed to the original URL; a raw search-replace updates the data but the on-disk CSS still references prod. `flush-css` clears the cache so the next page load regenerates it.
- **`wp cache flush` last** — clears any object cache populated during the search-replace passes.

Merge with existing `hooks:` block (same rules as Step 4 for `post-start`).

## Step 5 — WordPress only: bootstrap `wp-config.php`

Skip for Drupal.

Goal: on a fresh clone, `ddev start` should produce a working `wp-config.php` automatically, and per-project overrides (e.g. `$table_prefix`) should apply after every other config file has loaded.

Approach:

1. Copy `templates/wp-config-local.php` → `<wp-root>/wp-config-local.php` (committed).
2. Copy `templates/wp-config-override.php` → `<wp-root>/wp-config-override.php` (committed). Edit it to set whatever the user actually needs overridden (ask — the common one is `$table_prefix`).
3. Ensure `wp-config.php` is gitignored if it isn't already (it's the generated/local file).
4. Add a `pre-start` hook to `.ddev/config.yaml` so the local template is copied into place when `wp-config.php` is absent:

   ```yaml
   hooks:
     pre-start:
       - exec-host: test -f <wp-root>/wp-config.php || cp <wp-root>/wp-config-local.php <wp-root>/wp-config.php
   ```

   `<wp-root>` is the project root for a standard WordPress layout. Merge with any existing `hooks:` block (same rules as Step 4 for `post-start`).

5. Tell the user to edit `wp-config-override.php` to set their override (e.g. `$table_prefix = 'custom_';`) and commit both files.

If the user has an existing `wp-config.php` they want to keep, leave it alone and just add the `wp-config-override.php` + a `require_once` at the end of their `wp-config.php` (before `wp-settings.php`).

**On template drift:** the `pre-start` hook only seeds `wp-config.php` when the file is *missing*. Once seeded, `wp-config.php` diverges from `wp-config-local.php` over time — plugins like Solid Security / iThemes Security prepend their own config blocks, and users may hand-edit. This is expected, but it means later edits to `wp-config-local.php` do NOT propagate to the live file. If you change the template (e.g. to add a `defined()` guard), also apply the same edit to the user's live `wp-config.php`, or tell them to `rm wp-config.php && ddev start` to regenerate (they'll lose any plugin-injected blocks, which the plugin will re-add on next admin load).

**Why the WP_DEBUG defines are guarded:** DDEV's auto-generated `wp-config-ddev.php` already defines `WP_DEBUG`. A second `define('WP_DEBUG', ...)` in our file produces a PHP warning that fires during wp-config.php parsing — before WordPress has applied `WP_DEBUG_DISPLAY = false` — so the warning text prints into the response body *before* `<!DOCTYPE html>`. That knocks the browser into quirks mode and silently breaks Elementor/theme layout. The `if (!defined(...)) define(...)` guards in the template prevent this. Never "simplify" them away.

## Step 6 — Tell the user what's next

```
ddev restart
ddev pull <environment-name>
```

`ddev restart` triggers the new post-start hook so `ddev auth ssh` runs once and loads their keys for the session. On a fresh clone it will also run the `pre-start` hook that seeds `wp-config.php` from `wp-config-local.php` (WordPress).

## Notes on the template shape

- Both templates use `environment_variables` with `ssh_user` and `ssh_host` (lowercase). The `affinity-clone` script parses these case-insensitively but requires exactly one variable containing `HOST` and one containing `USER` — don't add a second (e.g. don't introduce a `remote_user` alongside `ssh_user`).
- Push commands are stubbed out with an "unsupported" message by default. This is deliberate: accidental `ddev push prod` is a disaster. Only enable pushes for non-production targets, and only if the user explicitly asks.
- Both templates use `files_import_command` (not `files_pull_command`) to rsync the files directory. This is deliberate: defining `files_pull_command` alongside an rsync that writes to the final destination makes DDEV run its default import step afterwards, which rsyncs from the (empty) `.ddev/.downloads/files/` staging dir into the project uploads/files dir with delete semantics — wiping everything just pulled. Omitting `files_pull_command` skips that default. For large sites the user may prefer `stage_file_proxy` instead — in that case, replace the `files_import_command` body with a no-op `echo` (see the islandhealth-style prod examples in the user's project checkouts).

## Tip: per-project key auto-loading (optional)

By default (after Step 4), `ddev start` runs `ddev auth ssh` via the `post-start` hook, loading all keys from `~/.ssh/` into `ddev-ssh-agent`. This is simple and covers most users.

If the user prefers to load only a specific key for this project — useful if they have many keys and hit `Too many authentication failures` / SSH `MaxAuthTries`, or they just want per-project isolation — they can override in `.ddev/config.local.yaml` (gitignored by default, so teammates are unaffected):

```yaml
hooks:
  post-start:
    - exec-host: ddev auth ssh -f ~/.ssh/<keyfile>
```

DDEV merges `config.local.yaml` with the committed `config.yaml`; `post-start` fires after every `ddev start`. Ask the user for the key path at that point — don't prompt for it up front.

Don't write this file from the skill. Mention it only if the user explicitly asks about per-project key loading, or if they've hit a `MaxAuthTries` / "Too many authentication failures" error while running `ddev pull`.

## Examples in the wild

If you need a reference for variations (SSH config aliases, custom backup paths, non-standard docroots), look at real provider files in the user's checkouts:

- Drupal, full rsync form: `~/Projects/medstaff/spaces/develop/.ddev/providers/stage.yaml`
- Drupal, SSH-alias form with `stage_file_proxy`: `~/Projects/islandhealth/spaces/189-search/.ddev/providers/prod.yaml`
- WordPress: `~/Projects/fpse/.ddev/providers/prod.yaml`
