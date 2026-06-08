---
name: ddev-setup
description: Sets up a functional DDEV environment for a Drupal or WordPress project. Creates DDEV provider YAML files (.ddev/providers/*.yaml) for `ddev pull`, wires `ddev auth ssh` into post-start, for WordPress projects bootstraps a committed `wp-config-local.php` + `wp-config-override.php` pair so fresh clones boot cleanly and `$table_prefix` (or similar) can be overridden last-in-cascade (with optional `stage_file_proxy` setup via the alleyinteractive plugin, gated on `WP_ENVIRONMENT_TYPE` so prod stays inert; ships an `IS_DDEV_PROJECT`-gated WP Mail SMTP / Mailpit override so dev mail can't leak), seeds a WordPress `.gitignore` and (for nested docroots) a `.ddev/homeadditions/.wp-cli/config.yml`, and for Drupal projects commits a minimal `default.settings.local.php` (with `stage_file_proxy` origin pre-filled) that DDEV copies into the gitignored `settings.local.php` on post-start (with a loud confirmation if `settings.php` is gitignored). For ALL projects (Drupal and WordPress) the setup includes a required PII (personally identifiable information) audit: after the first database pull, the local copy's schema and data are analyzed for PII, findings are recorded in a committed `docs/pii-audit.md`, and a project-specific `.ddev/scripts/sanitize-db.sh` is generated and wired into a `post-import-db` hook so every future pull is sanitized automatically. Use when the user wants to set up `ddev pull`, add a new environment (prod/stage/dev/cert) to a DDEV project, configure database and files sync from a remote server, fix a missing or broken provider, bootstrap a WordPress wp-config for a fresh clone, seed a WordPress `.gitignore`, set up `.ddev/homeadditions/.wp-cli/config.yml` for a nested-docroot WordPress site, route dev mail through Mailpit, set up Drupal's `settings.local.php` on a fresh clone, sanitize or anonymize a pulled database, audit a local database for PII, scrub production data from a local copy, or mentions needing a "DDEV provider" or "DDEV setup". The skill detects the project's CMS (Drupal vs WordPress) from the codebase and selects the correct templates.
---

# DDEV Setup

Bring a Drupal or WordPress project to a functional DDEV state. Concerns:

1. **Provider file** — `.ddev/providers/<name>.yaml` so `ddev pull <name>` can sync a database and user-uploaded files from a remote server.
2. **WordPress wp-config bootstrap** (WordPress only) — commit a `wp-config-local.php` that DDEV copies into `wp-config.php` on first start if it's missing, plus a `wp-config-override.php` that's included last in the config cascade so per-project overrides (notably `$table_prefix`) win. The seed also ships an `IS_DDEV_PROJECT`-gated WP Mail SMTP / Mailpit override so dev mail can't leak.
3. **WordPress `.gitignore` seed** (WordPress only) — drop in a baseline `.gitignore` covering WP dynamic files, security/cache/backup plugin spew, and `wp-config.php` itself. Merges with any existing `.gitignore` rather than replacing it.
4. **WordPress `.wp-cli/config.yml`** (WordPress only, subdirectory installs only) — write `.ddev/homeadditions/.wp-cli/config.yml` so `ddev wp` finds WordPress regardless of the CWD. Verify by running `ddev wp core version` before declaring success.
5. **Drupal settings.local.php bootstrap** (Drupal only) — commit a project-specific `sites/default/default.settings.local.php` (seeded from `templates/settings.local.php` with `stage_file_proxy` origin filled in), wire a `post-start` hook that copies it into the gitignored `sites/default/settings.local.php` on fresh clones, and uncomment the include block in `settings.php` so the override file actually loads. Requires `settings.php` to be tracked in git; if it isn't, the skill flags this and requires explicit confirmation before proceeding.
6. **PII audit + database sanitization** (REQUIRED, both CMSes) — after the first database pull, analyze the local copy for personally identifiable information (PII), record findings in a committed `docs/pii-audit.md`, generate a project-specific `.ddev/scripts/sanitize-db.sh` from the audit decisions, and wire it into a `post-import-db` hook so every future pull is sanitized automatically. Setup is not complete until this step has run (or the user has explicitly opted out, recorded in the final summary).

Templates live in `templates/` alongside this file.

## When to use

- The user asks to set up `ddev pull` on a project
- The user wants to add a new environment (e.g. `prod`, `stage`, `dev`, `cert`) to an existing DDEV project
- The user says the provider is missing or broken
- The user is being walked through by `affinity-clone` and the script reports "No DDEV provider found"
- The user wants the local database sanitized/anonymized, asks for a PII audit of a pulled database, or wants production data scrubbed from local copies

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
| SSH port | `22222` |
| Remote path | — (always ask; the composer/project root on the server) |
| Backup path | Same as Remote path — don't prompt. The dump is written there, rsynced, then removed. |

**Drupal-specific:**
- `FILES_SUBPATH` — default `web/sites/default/files`. Change if the project uses a different docroot (e.g. `docroot/sites/default/files`, or `sites/default/files` for non-composer sites). Only consulted if the user opts out of `stage_file_proxy` and switches `files_import_command` back to a real rsync (see Step 4d and the template comments). The default Drupal provider doesn't actually use this value at runtime, but it's still substituted into the file in case the user enables the rsync later.

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

## Step 4d — Drupal only: bootstrap `settings.local.php`

Goal: on a fresh clone, `ddev start` should produce a working `sites/default/settings.local.php` automatically, so per-developer overrides (local DB creds via DDEV's `settings.ddev.php`, dev services, disabled caches, etc.) apply without manual setup.

We ship a minimal `templates/settings.local.php` (alongside this SKILL.md) that's deliberately shorter than Drupal core's `example.settings.local.php`. It includes a `stage_file_proxy` origin (filled in at setup time), verbose error display, disabled CSS/JS aggregation, and null render/page caches. `settings.php` already contains a commented-out block that includes `settings.local.php` if present — we just need to:

1. Gather the production URL for `stage_file_proxy`.
2. Make sure the include block in `settings.php` is uncommented.
3. Commit the seed file to a non-ignored path so `post-start` can copy it into place on fresh clones.

### Step 4d.1 — Verify `settings.php` is tracked in git

**This workflow only works if `sites/default/settings.php` is tracked in the repo.** The include-block edit lives in `settings.php`, so if the file is gitignored, your change won't reach teammates or deployments — fresh clones will copy `settings.local.php` into place but `settings.php` won't include it, and any deploy that regenerates `settings.php` from scratch will silently drop the include.

From the project root, check:

```bash
git check-ignore -v web/sites/default/settings.php 2>/dev/null && echo "IGNORED" || echo "tracked"
git ls-files --error-unmatch web/sites/default/settings.php 2>/dev/null && echo "tracked in index" || echo "NOT tracked"
```

(Adjust `web/` to the project's docroot — `docroot/`, or empty for non-composer sites.)

**If `settings.php` is gitignored or untracked**, STOP and flag this loudly to the user before doing anything else. Use AskUserQuestion to make them confirm. Example wording:

> ⚠️ `sites/default/settings.php` is **gitignored** in this project. The `settings.local.php` bootstrap I'm about to set up edits `settings.php` to uncomment the `settings.local.php` include block — but since `settings.php` isn't tracked, that edit won't reach other developers or your deployment pipeline.
>
> This means manual deployment steps will be required: every environment (staging, production, teammates' fresh clones) will need someone to hand-edit `settings.php` to uncomment the include, or your deploy tooling needs to template it in. Otherwise the local-overrides block silently does nothing on those environments.
>
> Options:
> 1. **Proceed anyway** — I'll make the edit locally and you'll document the manual deploy step yourself.
> 2. **Track `settings.php` in git first** — remove it from `.gitignore` (or the `web/sites/default/.gitignore`), commit the canonical file, then I'll continue. Recommended.
> 3. **Skip the `settings.local.php` bootstrap** — leave things as-is.

Do not proceed past this question without an explicit choice. If they pick (1), record the decision in the final summary so they can't forget the manual deploy work.

### Step 4d.2 — Gather the production URL

Ask the user for the canonical production URL for `stage_file_proxy` — the scheme + host where missing files should be fetched from (e.g. `https://www.example.ca`). No trailing slash. This gets substituted into `{{PROD_URL}}` in the template.

If the user is unsure or the site doesn't have a public production URL yet, set it to an empty string and tell them to fill it in later (the `stage_file_proxy` module will simply do nothing until the origin is populated). Don't block setup on this.

### Step 4d.3 — Edit `settings.php`: empty-origin default + include block

Two edits to the committed `settings.php`, both at the bottom of the file:

**1. Add the empty-origin default for `stage_file_proxy`.** This is the production safety mechanism. Add it *above* the include block so that `settings.local.php` (which only exists on developer machines) can override it.

```php
// stage_file_proxy: globally inert by default. The settings.local.php file
// below (gitignored, dev-only) overrides this on local with the real origin.
// On prod, no settings.local.php exists, so the empty string wins and the
// module's subscriber bails on every request without side effects.
$config['stage_file_proxy.settings']['origin'] = '';
```

**2. Uncomment the existing `settings.local.php` include block.** Drupal's default `settings.php` contains this block, commented out:

```php
# if (file_exists($app_root . '/' . $site_path . '/settings.local.php')) {
#   include $app_root . '/' . $site_path . '/settings.local.php';
# }
```

Uncomment it (remove the leading `# ` from those three lines). If the block is missing entirely (some older or hand-tuned `settings.php` files lack it), append the uncommented form after the `$config[...]['origin']` line above.

Order matters: the `$config[]` default must come *before* the include, so `settings.local.php` can override it.

### Step 4d.4 — Commit the seed file

Read `~/.claude/skills/ddev-setup/templates/settings.local.php` (resolve `~` to the user's home directory). Replace `{{PROD_URL}}` with the value from Step 4d.2. Write the result to:

```
<docroot>/sites/default/default.settings.local.php
```

`<docroot>` is `web` for composer-based projects (`drupal/recommended-project`), `docroot` for some legacy layouts, or empty for non-composer sites. Read it from `.ddev/config.yaml`'s `docroot:` field.

**Why `default.settings.local.php` and not `example.settings.local.php`:** the file ships as the seed that `post-start` copies into the gitignored `settings.local.php`. Calling it `default.` (not `example.`) keeps it distinct from Drupal core's untouched `example.settings.local.php`, so the two coexist without confusion and so this file is obviously the project-specific one.

This file MUST be tracked in git. Verify it's not caught by a `sites/*/settings.local.php` glob in `.gitignore` (the standard Drupal gitignore uses that pattern, which will also match `default.settings.local.php`). If it is, add a negation:

```
# .gitignore
sites/*/settings.local.php
!sites/*/default.settings.local.php
```

### Step 4d.5 — Ensure `settings.local.php` (the runtime copy) is gitignored

The standard Drupal `.gitignore` (and `web/sites/.gitignore` shipped by `drupal/recommended-project`) already excludes `settings.local.php`. Verify with `git check-ignore -v <docroot>/sites/default/settings.local.php`. If it's not ignored, add `sites/*/settings.local.php` to the appropriate `.gitignore` — this file is per-developer and must never be committed. (Pair with the `!default.settings.local.php` negation from Step 4d.4 so the seed file stays tracked.)

### Step 4d.6 — Wire the copy into `post-start`

Add to `.ddev/config.yaml`:

```yaml
hooks:
  post-start:
    - exec-host: test -f <docroot>/sites/default/settings.local.php || cp <docroot>/sites/default/default.settings.local.php <docroot>/sites/default/settings.local.php
```

Merge with any existing `hooks: post-start:` block (same rules as Step 4 — append to the list, don't replace).

**Why `post-start` and not `pre-start`:** `pre-start` runs before the web container exists, so any error in the hook prevents DDEV from coming up at all. `post-start` runs after the container is healthy, so a copy failure produces a warning rather than a hard failure. The copy itself runs on the host, so container state doesn't matter — `post-start` is purely about failure isolation.

### Step 4d.7 — Remind the user to enable `stage_file_proxy`

The template references `stage_file_proxy.settings`, but that config only takes effect if the module is installed and enabled. Tell the user to:

```bash
ddev composer require drupal/stage_file_proxy
ddev drush en stage_file_proxy -y
ddev drush cex -y   # export the enabled state to config
```

If the project doesn't want `stage_file_proxy` (e.g. files are synced via `ddev pull`), they can comment out or remove the `$config['stage_file_proxy.settings']['origin']` line from `default.settings.local.php` before committing.

### Step 4d.8 — How prod stays safe (explain to the user)

The user will reasonably ask "wait, you're shipping `stage_file_proxy` to prod — what stops it from running there?" Walk them through the guarantees so they understand the design:

**What deploys to prod:**

| Deployed | Functional? | Notes |
|---|---|---|
| Module code (composer) | inert | bails on empty origin |
| Module enabled state (`core.extension.yml`) | inert | enabled but does nothing |
| `$config[...]['origin'] = ''` line in `settings.php` | yes — this is the safety | overrides any DB value |
| `default.settings.local.php` seed (contains prod URL as a literal) | inert | never `include`d on prod; PHP doesn't auto-discover sibling files |

**What does NOT deploy to prod:**

- `settings.local.php` — gitignored, only exists on dev machines after `ddev start` runs the post-start copy
- A working `origin` value in the active config / database — module's install default is empty, and nothing overwrites it server-side
- Any outbound HTTP from the module — the subscriber returns before any fetch logic runs

**Verified runtime behavior on prod** (from `stage_file_proxy` 4.0.x source, `src/EventSubscriber/StageFileProxySubscriber.php::checkFileOrigin`):

```php
$config = $this->configFactory->get('stage_file_proxy.settings');
$server = $config->get('origin');

// Quit if no origin given.
if (!$server) {
  return;
}
```

That early return is the first thing in the subscriber. Empty origin → silent return → no log entry, no exception, no response modification. There's also a second bailout a few lines down: if origin somehow gets set to prod's own hostname, the subscriber returns to prevent self-referential fetches.

**Bottom line:** the module runs on every request on prod (it's a `KernelEvents::REQUEST` listener at priority 240) but the runtime cost is ~2 lines of PHP and zero side effects. Production behavior is indistinguishable from "module not installed" except for the negligible subscriber dispatch overhead.

If the user needs zero-trace on prod (no module code, no enabled state in `core.extension.yml`), they need `config_split` — out of scope for this skill, but mention it as the next step if they ask.

## Step 5 — WordPress only: bootstrap `wp-config.php`

Skip for Drupal.

Goal: on a fresh clone, `ddev start` should produce a working `wp-config.php` automatically, and per-project overrides (e.g. `$table_prefix`) should apply after every other config file has loaded.

Approach:

1. Copy `templates/wp-config-local.php` → `<wp-root>/wp-config-local.php` (committed). Before writing the file, fetch a fresh set of salts and substitute them for the `{{SALTS}}` placeholder:
   - `curl -fsS https://api.wordpress.org/secret-key/1.1/salt/` returns 8 ready-to-paste `define(...)` lines.
   - Replace `{{SALTS}}` in the template body with the response verbatim, then write the file.
   - If the curl fails (no network), fall back to writing the placeholder block of 8 `define(... "put your unique phrase here")` lines and tell the user to grab fresh salts from the URL and paste them in. Do NOT commit "put your unique phrase here" silently.
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

> ⚠️ **If a `wp-config.php` already exists at the project root, the pre-start hook silently skips the copy** (`test -f ... ||` short-circuits). The user has to decide:
>
> - **Re-seed from the template** — delete the existing file and run `ddev restart` (or `cp wp-config-local.php wp-config.php` directly). Required if later steps add defines that the live file doesn't have yet (notably `STAGE_FILE_PROXY_URL` and `WP_ENVIRONMENT_TYPE` in Step 5b).
> - **Hand-merge** — paste the relevant defines from `wp-config-local.php` into the existing `wp-config.php`, preserving any plugin-injected blocks (Solid Security, iThemes Security, etc.) that the user wants to keep.
>
> Surfacing this is non-optional. If you skip it and the live `wp-config.php` is stale, every subsequent step that touches the runtime config (defines, gates, salts) will appear to succeed but produce no effect — and the symptom is silent: stage_file_proxy no-ops, environment-type checks don't fire, etc.

If the user has an existing `wp-config.php` they want to keep, leave it alone and just add the `wp-config-override.php` + a `require_once` at the end of their `wp-config.php` (before `wp-settings.php`).

**On template drift:** the `pre-start` hook only seeds `wp-config.php` when the file is *missing*. Once seeded, `wp-config.php` diverges from `wp-config-local.php` over time — plugins like Solid Security / iThemes Security prepend their own config blocks, and users may hand-edit. This is expected, but it means later edits to `wp-config-local.php` do NOT propagate to the live file. If you change the template (e.g. to add a `defined()` guard), also apply the same edit to the user's live `wp-config.php`, or tell them to `rm wp-config.php && ddev start` to regenerate (they'll lose any plugin-injected blocks, which the plugin will re-add on next admin load).

**Why the WP_DEBUG defines are guarded:** DDEV's auto-generated `wp-config-ddev.php` already defines `WP_DEBUG`. A second `define('WP_DEBUG', ...)` in our file produces a PHP warning that fires during wp-config.php parsing — before WordPress has applied `WP_DEBUG_DISPLAY = false` — so the warning text prints into the response body *before* `<!DOCTYPE html>`. That knocks the browser into quirks mode and silently breaks Elementor/theme layout. The `if (!defined(...)) define(...)` guards in the template prevent this. Never "simplify" them away.

**WP Mail SMTP / Mailpit override (ships in the template):** the template includes an `IS_DDEV_PROJECT`-gated block that defines `WPMS_*` constants pointing WordPress mail at DDEV's Mailpit (`localhost:1025`). These constants beat the plugin's database-stored mailer (often Mailgun/SendGrid on production sites), so even after a `ddev pull` brings down prod's mailer config, dev mail can't leak to real recipients. The block is gated on `IS_DDEV_PROJECT === "true"`, not `WP_ENVIRONMENT_TYPE`, because it's a DDEV-runtime feature rather than an environment-type concern — and the gate ensures the constants only fire inside DDEV containers. Harmless no-op if WP Mail SMTP isn't installed. Mailpit inbox: `https://<project>.ddev.site:8026`. If the user explicitly does NOT want WP Mail SMTP routed (rare — e.g. they're actively testing a real provider's API integration locally), tell them to comment the block out in `wp-config-local.php`.

## Step 5b — WordPress only: bootstrap `stage_file_proxy` (optional)

Goal: let local clones pull missing uploads on demand from production via the [alleyinteractive/stage-file-proxy](https://github.com/alleyinteractive/stage-file-proxy) plugin, without ever activating that behavior in production.

This is **optional**. Ask the user whether they want it — if files are small and `ddev pull` is fine, skip. If uploads are large (hundreds of MB+) and a full rsync on every pull is painful, this is the right tool.

### Step 5b.1 — Gather the production URL

Ask the user for the scheme + host where missing uploads should be fetched from (e.g. `https://www.example.ca`). No trailing slash. This gets substituted into `{{STAGE_FILE_PROXY_URL}}` in the `wp-config-local.php` template.

If they decline `stage_file_proxy`, set the value to an empty string — the gate in the template still applies, and the plugin no-ops on an empty URL anyway. (Or strip the block entirely — your call.)

### Step 5b.2 — Verify the wp-config bootstrap is in place

Step 5 must have run first. The `wp-config-local.php` template ships with two pieces that make this safe:

1. `define("WP_ENVIRONMENT_TYPE", "local")` near the top — flags this environment as non-production. The committed seed only ever becomes the gitignored `wp-config.php` on developer machines (via the `pre-start` copy), so prod never sees it.
2. A gated `STAGE_FILE_PROXY_URL` define:

   ```php
   if (defined("WP_ENVIRONMENT_TYPE") && WP_ENVIRONMENT_TYPE !== "production") {
       if (!defined("STAGE_FILE_PROXY_URL")) define("STAGE_FILE_PROXY_URL", "{{STAGE_FILE_PROXY_URL}}");
   }
   ```

   `WP_ENVIRONMENT_TYPE` is checked as a raw constant (not via `wp_get_environment_type()`) because WordPress core isn't loaded yet at wp-config.php parse time. If the constant is **undefined**, the gate fails closed — that matches core's own default (`wp_get_environment_type()` returns `'production'` when unset), so prod is safe by omission.

> ⚠️ **Important caveat about the constant gate.** The current upstream [alleyinteractive/stage-file-proxy](https://github.com/alleyinteractive/stage-file-proxy) (`Version: 100`) reads its origin URL from `wp_options.sfp_url` via `get_option( 'sfp_url' )`. **It does not consult the `STAGE_FILE_PROXY_URL` constant.** With that plugin, the gate above is decorative — defining the constant does not enable the proxy, and not defining it does not disable it. The actual runtime config lives in a DB option (see Step 5b.3 below).
>
> Some forks (notably Automattic VIP's) do read the constant. If you switch the plugin, verify by reading the plugin source for `STAGE_FILE_PROXY_URL`; if the constant is consulted, the gate becomes actually protective and the constant-vs-option discussion in Step 5b.3 collapses.
>
> Why we still ship the constant in the template: defense-in-depth for forks that respect it, plus it's a useful runtime signal for project code that wants to branch on "is this a local proxy environment?". It does no harm in the alleyinteractive case — just doesn't gate anything.

### Step 5b.3 — Install and configure the plugin

```bash
ddev composer require alleyinteractive/stage-file-proxy
```

If the project isn't composer-managed, fall back to manual install in `wp-content/plugins/` (e.g. `git clone https://github.com/alleyinteractive/stage-file-proxy.git` into that dir, then remove the nested `.git`).

**Then configure the origin URL and mode** (alleyinteractive plugin — skip if you switched to a constant-respecting fork):

```bash
ddev wp plugin activate stage-file-proxy
ddev wp option update sfp_url  https://www.{{PROD_DOMAIN}}/wp-content/uploads/
ddev wp option update sfp_mode download
```

Three non-obvious gotchas:

- **The trailing `/wp-content/uploads/` matters, not optional.** The plugin appends a *relative* path (without `/wp-content/uploads/`) to whatever URL is stored in `sfp_url`. If you set it to just `https://www.example.org`, the redirects come out as `https://www.example.org2022/01/Admin.svg` — missing slash, missing path prefix, broken.
- **Without `sfp_url` set, the plugin dies loudly.** Any request that reaches the plugin's dispatcher with no `sfp_url` produces a `die( 'SFP tried to load, but encountered an error' )`. This is the symptom you'll see if `sfp_url` ever ends up empty (which it will after every `ddev pull` — see Step 5b.4).
- **Use `download` mode, not the default `header` mode.** The plugin's default mode emits a 302 redirect from local to prod for every missing upload. The 302 response carries WordPress's default `Content-Type: text/html`, and Chromium's Opaque Response Blocking treats that as a hostile cross-origin response for `<img>` fetches — images silently fail with `net::ERR_BLOCKED_BY_ORB` (Network tab only; nothing in the JS console). `download` mode has the plugin fetch the file server-side and serve it from the local origin with the correct `image/*` content-type, which sidesteps ORB *and* builds a local upload cache on first hit. Firefox/Safari don't have ORB and won't show the symptom, so this often only surfaces once someone tries to view the site in Chrome.

On production, leaving `sfp_url` unset is harmless **because nginx serves uploads files directly without invoking PHP**; the plugin only runs when a request falls through to `index.php`, which on prod means "the file is genuinely missing." See Step 5b.5 for the full safety story.

### Step 5b.4 — Wire `sfp_url` (and optionally activation) into `post-import-db`

Both `wp_options.active_plugins`, `wp_options.sfp_url`, and `wp_options.sfp_mode` get pulled down by `ddev pull` from prod. Whatever you set locally is wiped on every pull and replaced with prod's value. That has to be reasserted via a `post-import-db` hook, or local file fetches break silently after the next pull.

**`sfp_url` and `sfp_mode` always need the hook.** Prod's `sfp_url` is empty (you didn't configure it on prod — see Step 5b.3 and Step 5b.5), so every pull resets local back to empty and the plugin starts `die()`-ing on missing-file requests. Same for `sfp_mode` — without it, the option falls back to `header` and Chrome ORB starts blocking images again.

**Whether the activation row also needs the hook depends on which posture you pick:**

#### Posture A (Recommended): activate stage-file-proxy on prod too

```bash
ddev wp plugin activate stage-file-proxy   # local
wp plugin activate stage-file-proxy        # prod (one-time, in prod's environment)
```

Then in `.ddev/config.yaml`:

```yaml
hooks:
  post-import-db:
    # ... existing search-replace lines from Step 4c ...
    - exec: wp option update sfp_url  https://www.{{PROD_DOMAIN}}/wp-content/uploads/
    - exec: wp option update sfp_mode download
```

Place both lines after the search-replace lines but before `wp cache flush`.

Why activating on prod is fine despite "the plugin is for local-only use":

- **Prod's runtime is structurally inert.** On prod, `/wp-content/uploads/<file>` requests are served by nginx directly from disk via `try_files $uri ...`. PHP is only invoked when the file is genuinely absent — and at that point the plugin sees an empty `sfp_url` and `die()`s with an obvious error message that's easy to spot in logs. No outbound HTTP. No data exfiltration vector. Nothing happens for normal traffic.
- **No DB direction-of-travel footgun.** If anyone ever pushes a local DB upward (launches, content syncs, etc.), the local activation flag goes with it. If prod is already showing the plugin as active, that push is a no-op for activation state; if prod is showing it as deactivated, the push silently re-activates it and you may not notice. Activating-everywhere removes that asymmetry.
- **Honesty.** The plugins admin page reflects what's actually installed in every environment.

#### Posture B: deactivate on prod, reactivate via hook

Only useful if the user has a strong organisational reason to keep prod's plugins list "clean" — e.g. a compliance audit that scans active plugins, or a deploy pipeline that hard-sets `active_plugins` from a manifest so the deactivation is actually enforced.

```yaml
hooks:
  post-import-db:
    # ... existing search-replace lines from Step 4c ...
    - exec: wp plugin activate stage-file-proxy
    - exec: wp option update sfp_url  https://www.{{PROD_DOMAIN}}/wp-content/uploads/
    - exec: wp option update sfp_mode download
```

All three lines required — without the activation line, the pull leaves the plugin inactive; without the `sfp_url` line, the plugin is active but dies on every miss; without the `sfp_mode` line, Chrome ORB starts blocking proxied images. Adds an extra moving part that Posture A doesn't have: if the activation line ever silently fails (plugin slug typo, plugin file missing, etc.), local file fetches break with no clear pointer to plugin state.

### Step 5b.5 — How prod stays safe (explain to the user)

The real protection is **structural, not config-gated**: on prod, nginx serves `/wp-content/uploads/<file>` directly from disk via `try_files $uri ...`. PHP is only invoked when the file is genuinely missing. The plugin only fires inside PHP — so on normal prod traffic (where uploads files exist on disk), the plugin's dispatcher code never runs.

The layers (assuming Posture A — "active everywhere" — from Step 5b.4):

| Layer | Behaviour on prod | Notes |
|---|---|---|
| nginx `try_files` for `/wp-content/uploads/<file>` | serves file directly, no PHP | This is the primary safety. PHP doesn't run, plugin doesn't run. |
| Plugin code (composer/in-tree) | loaded into WP but never dispatched | The early-bind check (`if ( stripos( $_SERVER['REQUEST_URI'], '/wp-content/uploads/' ) !== false ) sfp_expect();`) only matters if PHP is invoked for that path. |
| `wp_options.sfp_url` on prod | empty (never set) | If a genuinely-missing-file request ever does reach PHP, the plugin sees empty `sfp_url` and `die()`s with an explicit error message rather than doing anything. Loud, obvious failure mode; no outbound HTTP. |
| `STAGE_FILE_PROXY_URL` constant | never defined on prod | Gated on `WP_ENVIRONMENT_TYPE !== 'production'`. Decorative for the alleyinteractive plugin (it doesn't read this constant); actually protective for forks that do. |
| `wp-config-local.php` seed (contains prod URL as a literal) | never `include`d on prod | Prod's `wp-config.php` is hand-written or templated by deploy tooling, not seeded from this file. |

**What does NOT deploy to prod:**

- `wp-config.php` — gitignored, only exists on dev machines after `ddev start` runs the pre-start copy.
- `WP_ENVIRONMENT_TYPE` — only defined inside `wp-config-local.php`, which only lands on local.
- A non-empty `sfp_url` option — you never set it on prod; `ddev pull` only goes local-←-prod, so prod's empty state is authoritative.

**Bottom line:** the design fails *quietly* on prod under normal traffic (nginx serves the files, plugin never runs) and fails *loudly* on prod under abnormal traffic (a missing-file request reaches PHP, the plugin dies with an explicit error — easy to spot in logs, no security impact). It's not a code-level gate the way Drupal's `$config['origin'] = ''` is, but it doesn't need to be — the structural property (files exist on prod) does the work.

If you want a stronger code-level gate, switch to a fork that reads `STAGE_FILE_PROXY_URL` and the constant block in `wp-config-local.php` becomes actually protective. The template already ships the gate for that case.

## Step 5c — WordPress only: seed `.gitignore`

Drop in a baseline `.gitignore` covering WordPress dynamic files, security/cache/backup plugin spew, and `wp-config.php` itself (which is correctly gitignored — Step 5 makes it the local/generated file).

### Step 5c.1 — Detect docroot layout

WordPress lives in one of two layouts:

1. **Root install** — `wp-config.php`, `wp-login.php`, `wp-includes/` directly in the project root. The `.gitignore` paths have no prefix.
2. **Subdirectory install** — WordPress is under `web/`, `public_html/`, `www/`, or similar. The `.gitignore` paths need that prefix (e.g. `web/wp-content/uploads/`).

Read `docroot:` from `.ddev/config.yaml` to determine which. Empty or missing → root install. Otherwise, that value is the subdirectory.

### Step 5c.2 — Render the template

Read `~/.claude/skills/ddev-setup/templates/wordpress.gitignore` (resolve `~`).

Substitute `{{WP_PREFIX}}`:
- Root install → empty string (`""`)
- Subdirectory install → `<subdir>/` (e.g. `web/`)

Substitute `{{WP_CLI_SUBDIR_LINE}}`:
- Root install → empty string (delete the line entirely)
- Subdirectory install → `/<subdir>/wp-cli.yaml` (so a stray per-env `wp-cli.yaml` inside the docroot is also ignored — distinct from the committed `.ddev/homeadditions/.wp-cli/config.yml` from Step 5d)

After substitution, scan for any remaining `{{` — fail loudly if any token wasn't replaced.

### Step 5c.3 — Write or merge

- If no `.gitignore` exists at the project root, write the rendered template there.
- If one exists, **merge — don't replace.** Read the existing file, append only the entries from the template that aren't already present (compare line-by-line, ignoring blank lines and comments). Preserve every project-specific entry already in the file. If existing entries conflict with template entries (e.g. a different `wp-content/uploads/` rule), show the conflict to the user and ask before editing.

Verify `wp-config.php` ends up gitignored (this is Step 5's requirement). If it isn't, add it explicitly.

## Step 5d — WordPress only: seed `.ddev/homeadditions/.wp-cli/config.yml` (subdirectory installs)

**Only applies when WordPress is in a subdirectory.** Skip entirely for root installs — DDEV's default `path: /var/www/html` works fine when WordPress is at the docroot.

### Step 5d.1 — Decide whether it's needed

Check the `docroot:` value in `.ddev/config.yaml`:
- Empty or missing → **skip this step**. Root install. WP-CLI defaults already work.
- Non-empty (e.g. `web`) → **proceed**.

The reason this file matters: without it, `ddev wp <command>` runs from `/var/www/html` and can't find WordPress (which is at `/var/www/html/<subdir>`). The user sees confusing errors like `Error: This does not seem to be a WordPress installation.` Setting `path:` in a homeadditions wp-cli config makes `ddev wp` work transparently from any directory.

### Step 5d.2 — Write the config

Create `.ddev/homeadditions/.wp-cli/config.yml` with:

```yaml
path: /var/www/html/<subdir>
```

Substitute `<subdir>` with the actual docroot value (e.g. `path: /var/www/html/web`). DDEV copies the `homeadditions/` tree into the web container's home directory on start, so this lands at `~/.wp-cli/config.yml` inside the container.

If the file already exists, leave it alone and report its contents to the user — they may have set additional WP-CLI defaults.

### Step 5d.3 — Verify WP-CLI works before continuing

After writing the file, ask the user to run:

```bash
ddev restart
ddev wp core version
```

The expected output is a WordPress version string (e.g. `6.7.2`). If they get `Error: This does not seem to be a WordPress installation` or similar, something is mismatched — most likely the `path:` value doesn't actually point at a WordPress install. Confirm:

1. The `docroot:` in `.ddev/config.yaml` is correct (matches the actual subdirectory).
2. WordPress files (`wp-load.php`, `wp-includes/`) are present in that subdirectory.
3. If the project is composer-managed with `johnpbloch/wordpress`, WordPress may not have been installed yet — run `ddev composer install` first.

Do not move on until `ddev wp core version` returns cleanly. Every downstream WordPress automation (the search-replace hook in Step 4c, the `stage_file_proxy` config in Step 5b.3, the user's day-to-day wp-cli usage) depends on this working.

## Step 6 — REQUIRED: PII audit & database sanitization (both CMSes)

Once the provider works, the pulled database lands locally with all of production's PII intact — user emails, form submissions, order data, comment authors. This step is **required for every Drupal and WordPress setup**: pull a database, analyze the actual schema and data for PII, make tactical per-project decisions about what needs sanitizing, and wire those decisions into a committed `.ddev/scripts/sanitize-db.sh` that runs on every future pull via a `post-import-db` hook.

Do not declare setup complete without this step. If the user explicitly opts out, record the opt-out prominently in the final summary (Step 7) — never skip it silently.

The audit is **data-driven, not checklist-driven**: only tables that actually contain PII in *this* project get sanitization rules. The checklists below tell you where to look, not what to scrub.

### Step 6.1 — Pull a database

```bash
ddev restart        # picks up the new provider + hooks
ddev pull <env>
```

> 🚨 **If the pull source is production, do NOT run `ddev pull <env>` yourself.** `ddev pull` from a production environment connects to the production server, which the assistant must never do (this matches the user's global no-production-access rule, and is the safe default for any user). Ask the user to run it themselves — suggest typing `! ddev pull <env>` in the prompt so the output lands in the conversation — and continue once it completes. Pulls from stage/dev/demo environments may be run directly.

Everything after this point runs **only against the local imported copy** via `ddev mysql` / `ddev drush` / `ddev wp` — never against the remote.

### Step 6.2 — Schema scan

Scan column names for PII patterns (works for both CMSes):

```bash
ddev mysql -e "SELECT table_name, column_name FROM information_schema.columns
  WHERE table_schema = 'db' AND (
    column_name LIKE '%mail%' OR column_name LIKE '%phone%' OR column_name LIKE '%tel%'
    OR column_name LIKE '%address%' OR column_name LIKE '%postal%' OR column_name LIKE '%zip%'
    OR column_name LIKE '%first_name%' OR column_name LIKE '%last_name%' OR column_name LIKE '%full_name%'
    OR column_name LIKE '%birth%' OR column_name LIKE '%dob%' OR column_name LIKE '%gender%'
    OR column_name LIKE '%ssn%' OR column_name LIKE '%sin%' OR column_name LIKE '%passport%'
    OR column_name LIKE '%credit%' OR column_name LIKE '%iban%'
    OR column_name = 'ip' OR column_name LIKE '%ip_address%' OR column_name LIKE '%hostname%'
  ) ORDER BY table_name, column_name"
```

And list all tables with row counts to spot known PII-bearing tables by name (approximate counts are fine for triage):

```bash
ddev mysql -e "SELECT table_name, table_rows FROM information_schema.tables
  WHERE table_schema = 'db' ORDER BY table_name"
```

### Step 6.3 — Known-table checklists (CMS-specific)

Cross-reference the table listing against these. Presence of a table means *investigate it* — the audit decides whether it actually holds PII in this project.

**Drupal:**

| Table(s) | What's in there |
|---|---|
| `users_field_data` | name, mail, init, pass — handled by the `drush sql:sanitize` base layer |
| `user__field_*` | custom profile fields (phone, address, job title...) |
| `webform_submission`, `webform_submission_data` | form submissions — usually the biggest PII concentration in a Drupal site |
| `contact_message` | core contact form messages |
| `comment_field_data` | comment author name, mail, hostname (IP) |
| `profile__*` | profile module / Commerce customer profiles (billing addresses) |
| `commerce_order`, `commerce_order_item` | order emails, totals tied to identities |
| `watchdog` | dblog — IPs, usernames, sometimes submitted values in messages |
| `sessions` | session tokens + IPs |
| `history` | per-user read tracking (low sensitivity, note it) |

⚠️ **Revision twins:** every flagged fieldable-entity table has `_revision` twins (e.g. `user__field_phone` → `user_revision__field_phone`) that retain pre-edit PII. Any rule on a field table must also cover its revision table.

**WordPress** (prefix shown as `wp_`; respect the project's actual `$table_prefix` — get it with `ddev wp db prefix`):

| Table(s) | What's in there |
|---|---|
| `wp_users`, `wp_usermeta` | emails, names, password hashes; billing/shipping meta, phone, session tokens (IPs) |
| `wp_comments`, `wp_commentmeta` | author email, IP, URL |
| Gravity Forms: `wp_gf_entry`, `wp_gf_entry_meta`, `wp_gf_entry_notes` | form submissions + submitter IP |
| WPForms: `wp_wpforms_entries`, `wp_wpforms_entry_fields` | form submissions |
| Ninja Forms: `wp_nf3_*` + `nf_sub` posts | form submissions |
| Contact Form 7 + Flamingo: `flamingo_inbound`/`flamingo_contact` posts, `wp_db7_forms` (CFDB7) | stored messages — CF7 alone stores nothing; storage plugins do |
| Fluent Forms: `wp_fluentform_submissions`, `wp_fluentform_entry_details` | form submissions |
| WooCommerce: `wp_wc_orders`, `wp_wc_order_addresses`, `wp_wc_customer_lookup`, `wp_postmeta` (`_billing_*`/`_shipping_*`), `wp_woocommerce_sessions` | full customer identity + addresses; legacy orders live in postmeta |
| Newsletters: `wp_mailpoet_subscribers`, `wp_newsletter` | subscriber emails/names |
| Security/audit logs: `wp_aiowps_*`, `wp_wsal_*`, `wp_itsec_logs`, `wp_actionscheduler_logs` | IPs, usernames, login attempts |

### Step 6.4 — Sample-data verification

Generic value columns (`*_meta.meta_value`, `webform_submission_data.value`, log `message` columns) can't be classified by name alone. Confirm or clear them with bounded sampling — counts only, never values:

```bash
# How many rows look like they contain an email address?
ddev mysql -e "SELECT COUNT(*) FROM db.wp_gf_entry_meta
  WHERE meta_value REGEXP '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\\\.[A-Za-z]{2,}' LIMIT 1"
# Phone-ish patterns:
ddev mysql -e "SELECT COUNT(*) FROM db.webform_submission_data
  WHERE value REGEXP '\\\\+?[0-9][0-9() .-]{7,}[0-9]'"
```

Classify every finding: **confirmed PII** (name and sampled data both indicate PII), **likely** (name suggests it, sampling inconclusive — treat as PII), or **clean** (inspected, no PII).

> 🔒 **Never print actual PII into the conversation, the audit doc, or logs.** Report table/column names and match counts only — "`gf_entry_meta`: 4,212 rows, 318 match email pattern" — never the matched values. Don't `SELECT` raw column values for eyeballing; use `COUNT(*)`, `LENGTH()`, or `REGEXP` predicates instead.

### Step 6.5 — Present findings and decide actions

Group findings into categories (user accounts, form submissions, commerce/orders, comments, logs/sessions, custom fields) and use AskUserQuestion per category with these options:

- **Truncate** — wipe the table(s). Right call for form submissions, logs, and sessions: local dev rarely needs real submission content, and empty tables can't leak.
- **Anonymize in place** — rewrite PII columns with fake values, preserving row counts and data shape. Right call for users (accounts must stay loggable), comments (threads should render), and orders (commerce flows need data to exercise).
- **Keep as-is** — only with an explicit justification, recorded in the audit doc.

Recommend per category based on what the data *is*: truncating `webform_submission_data` is usually right; truncating `users` never is. If the site is e-commerce, ask whether developers need realistic order volumes (anonymize) or not (truncate).

For WordPress, also ask whether any team accounts should keep their real email addresses (a `KEEP_EMAILS` whitelist in the script — safe because Step 5's Mailpit override means local mail can't leave the machine anyway). For Drupal, the same effect is a post-sanitize `UPDATE` re-asserting specific accounts.

### Step 6.6 — Write the audit doc

Render `templates/pii-audit.md` (resolve `~/.claude/skills/ddev-setup/templates/`) into `<project-root>/docs/pii-audit.md` (create `docs/` if needed; **committed**). Fill in: project, date, source environment, the findings table (table / columns / classification / row count / decision / implemented rule), the "verified clean" list (so future audits don't re-litigate), and leave the verification log rows for Step 6.9. Every rule that lands in the sanitize script must trace back to a row in this document.

### Step 6.7 — Generate the sanitize script

Read the CMS-matching template — `templates/sanitize-db-drupal.sh` or `templates/sanitize-db-wordpress.sh` — and write `<project-root>/.ddev/scripts/sanitize-db.sh` (**committed**, create `.ddev/scripts/` if needed):

1. Replace `{{AUDIT_DATE}}` and `{{ENVIRONMENT}}` in the header comment.
2. Keep the base layer as-is (Drupal: `drush sql:sanitize`; WordPress: users/usermeta/comments anonymization). WordPress: replace `{{KEEP_EMAILS}}` with the whitelist from Step 6.5, or an empty string.
3. In the project-specific section, uncomment/adapt only the blocks matching the decisions from Step 6.5, with the real table names (and `_revision` twins for Drupal fields). Delete example blocks that don't apply.
4. Verify no `{{` remains, then `bash -n` the result.

The `IS_DDEV_PROJECT` guard at the top of both templates is non-negotiable — it makes the script refuse to run outside a DDEV container, so it can never be pointed at a remote database. Never remove it.

### Step 6.8 — Wire the hook into `post-import-db`

Add to `.ddev/config.yaml` (same merge rules as Step 4 — append, don't replace):

```yaml
hooks:
  post-import-db:
    - exec: bash .ddev/scripts/sanitize-db.sh
```

Ordering matters:

- **WordPress:** the sanitize line goes **after** the Step 4c search-replace lines and the Step 5b `sfp_*` lines, **before** the final `wp cache flush` (the script flushes again itself; keeping the hook-level flush last is still correct if other lines follow).
- **Drupal:** typically the first (only) `post-import-db` entry.

### Step 6.9 — Verify

Run it once for real and prove it worked:

```bash
ddev exec bash .ddev/scripts/sanitize-db.sh
```

Then spot-check with counts (never raw values):

```bash
# Drupal — expect 0 (or exactly the whitelisted count):
ddev mysql -e "SELECT COUNT(*) FROM db.users_field_data WHERE mail NOT LIKE '%@localhost' AND mail <> '' AND mail IS NOT NULL"
# WordPress — expect 0 (or exactly the whitelisted count):
ddev mysql -e "SELECT COUNT(*) FROM db.wp_users WHERE user_email NOT LIKE '%@example.test'"
# Truncated tables — expect 0:
ddev mysql -e "SELECT COUNT(*) FROM db.webform_submission_data"
```

Record the results in the verification log of `docs/pii-audit.md`. Remind the user to commit `docs/pii-audit.md`, `.ddev/scripts/sanitize-db.sh`, and the `.ddev/config.yaml` hook change together.

## Step 7 — Tell the user what's next

```
ddev restart
ddev pull <environment-name>
```

`ddev restart` triggers the new post-start hook so `ddev auth ssh` runs once and loads their keys for the session. On a fresh clone it will also run the `pre-start` hook that seeds `wp-config.php` from `wp-config-local.php` (WordPress), or the `post-start` hook that seeds `settings.local.php` from `default.settings.local.php` (Drupal). Every `ddev pull` now ends with the `post-import-db` sanitization pass from Step 6, so the local copy never retains production PII.

If the user chose to proceed with the `settings.local.php` bootstrap despite `settings.php` being gitignored (Step 4d.1, option 1), restate the manual deployment requirement here so it's the last thing they see: every other environment needs `settings.php` hand-edited (or templated by deploy tooling) to uncomment the `settings.local.php` include block, or the bootstrap silently does nothing there.

If the user opted out of the PII audit (Step 6), restate that loudly here: the local database contains unsanitized production PII, and every future `ddev pull` will refresh it. Recommend they revisit with "sanitize the database" when ready.

## Notes on the template shape

- Both templates use `environment_variables` with `ssh_user` and `ssh_host` (lowercase). The `affinity-clone` script parses these case-insensitively but requires exactly one variable containing `HOST` and one containing `USER` — don't add a second (e.g. don't introduce a `remote_user` alongside `ssh_user`).
- Push commands are stubbed out with an "unsupported" message by default. This is deliberate: accidental `ddev push prod` is a disaster. Only enable pushes for non-production targets, and only if the user explicitly asks.
- Both templates use `files_import_command` (not `files_pull_command`) for the files-directory handoff. This is deliberate: defining `files_pull_command` alongside an `files_import_command` that writes to the final destination makes DDEV run its default import step afterwards, which rsyncs from the (empty) `.ddev/.downloads/files/` staging dir into the project uploads/files dir with delete semantics — wiping local files. Omitting `files_pull_command` skips that default.
- **Drupal default is a no-op `echo` that defers to `stage_file_proxy`.** The Drupal template ships `files_import_command` as a stub that prints a message saying this environment relies on `stage_file_proxy` (configured in `settings.local.php` from Step 4d). This pairs with the `default.settings.local.php` template's `$config['stage_file_proxy.settings']['origin']` line. If the user wants a real rsync instead (small sites, or environments without HTTP access to production), tell them to replace the body per the comment block inside the template — and remind them to remove the `stage_file_proxy` origin config or disable the module so the two mechanisms don't both run.
- WordPress also supports `stage_file_proxy` (Step 5b) via the [alleyinteractive/stage-file-proxy](https://github.com/alleyinteractive/stage-file-proxy) plugin. If the user opts in, the `files_import_command` can be neutralized the same way the Drupal default is — see the comment block in `wordpress.yaml`.

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
