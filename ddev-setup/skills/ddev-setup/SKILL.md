---
name: ddev-setup
description: Sets up a functional DDEV environment for a Drupal or WordPress project. Creates DDEV provider YAML files (.ddev/providers/*.yaml) for `ddev pull`, wires `ddev auth ssh` into post-start, for WordPress projects bootstraps a committed `wp-config-local.php` + `wp-config-override.php` pair so fresh clones boot cleanly and `$table_prefix` (or similar) can be overridden last-in-cascade (with optional `stage_file_proxy` setup via the alleyinteractive plugin, gated on `WP_ENVIRONMENT_TYPE` so prod stays inert), and for Drupal projects commits a minimal `default.settings.local.php` (with `stage_file_proxy` origin pre-filled) that DDEV copies into the gitignored `settings.local.php` on post-start (with a loud confirmation if `settings.php` is gitignored). Use when the user wants to set up `ddev pull`, add a new environment (prod/stage/dev/cert) to a DDEV project, configure database and files sync from a remote server, fix a missing or broken provider, bootstrap a WordPress wp-config for a fresh clone, set up Drupal's `settings.local.php` on a fresh clone, or mentions needing a "DDEV provider" or "DDEV setup". The skill detects the project's CMS (Drupal vs WordPress) from the codebase and selects the correct templates.
---

# DDEV Setup

Bring a Drupal or WordPress project to a functional DDEV state. Two concerns:

1. **Provider file** — `.ddev/providers/<name>.yaml` so `ddev pull <name>` can sync a database and user-uploaded files from a remote server.
2. **WordPress wp-config bootstrap** (WordPress only) — commit a `wp-config-local.php` that DDEV copies into `wp-config.php` on first start if it's missing, plus a `wp-config-override.php` that's included last in the config cascade so per-project overrides (notably `$table_prefix`) win.
3. **Drupal settings.local.php bootstrap** (Drupal only) — commit a project-specific `sites/default/default.settings.local.php` (seeded from `templates/settings.local.php` with `stage_file_proxy` origin filled in), wire a `post-start` hook that copies it into the gitignored `sites/default/settings.local.php` on fresh clones, and uncomment the include block in `settings.php` so the override file actually loads. Requires `settings.php` to be tracked in git; if it isn't, the skill flags this and requires explicit confirmation before proceeding.

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

If the user has an existing `wp-config.php` they want to keep, leave it alone and just add the `wp-config-override.php` + a `require_once` at the end of their `wp-config.php` (before `wp-settings.php`).

**On template drift:** the `pre-start` hook only seeds `wp-config.php` when the file is *missing*. Once seeded, `wp-config.php` diverges from `wp-config-local.php` over time — plugins like Solid Security / iThemes Security prepend their own config blocks, and users may hand-edit. This is expected, but it means later edits to `wp-config-local.php` do NOT propagate to the live file. If you change the template (e.g. to add a `defined()` guard), also apply the same edit to the user's live `wp-config.php`, or tell them to `rm wp-config.php && ddev start` to regenerate (they'll lose any plugin-injected blocks, which the plugin will re-add on next admin load).

**Why the WP_DEBUG defines are guarded:** DDEV's auto-generated `wp-config-ddev.php` already defines `WP_DEBUG`. A second `define('WP_DEBUG', ...)` in our file produces a PHP warning that fires during wp-config.php parsing — before WordPress has applied `WP_DEBUG_DISPLAY = false` — so the warning text prints into the response body *before* `<!DOCTYPE html>`. That knocks the browser into quirks mode and silently breaks Elementor/theme layout. The `if (!defined(...)) define(...)` guards in the template prevent this. Never "simplify" them away.

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

### Step 5b.3 — Install the plugin

```bash
ddev composer require alleyinteractive/stage-file-proxy
```

If the project isn't composer-managed, fall back to manual install in `wp-content/plugins/`. The plugin code is inert without `STAGE_FILE_PROXY_URL` defined, so shipping it to prod is fine — same posture as Drupal's `stage_file_proxy` module in Step 4d.

### Step 5b.4 — Activate the plugin on local only

WordPress stores active plugins in `wp_options.active_plugins`, which gets pulled down by `ddev pull` from prod. Two approaches:

**Recommended:** Leave the plugin deactivated in prod's DB. Add an activation step to the `post-import-db` hook from Step 4c, so every `ddev pull` reactivates it locally after the prod DB lands:

```yaml
hooks:
  post-import-db:
    # ... existing search-replace lines from Step 4c ...
    - exec: wp plugin activate stage-file-proxy
```

Place it after the search-replace lines but before `wp cache flush` (so the cache flush also clears anything the plugin's activation hook touched).

**Alternative:** If the user can't or won't keep it deactivated in prod's DB (e.g. they manage activation via a deploy script that hard-sets the list), they can rely on the `STAGE_FILE_PROXY_URL` gate alone. The plugin runs on every request in prod, sees no URL, and bails. Same end state as the Drupal empty-origin pattern. Tell them this is acceptable but less defense-in-depth than keeping it deactivated.

### Step 5b.5 — How prod stays safe (explain to the user)

Same shape as Step 4d.8 for Drupal. The layers:

| Deployed | Functional on prod? | Notes |
|---|---|---|
| Plugin code (composer) | inert | no `STAGE_FILE_PROXY_URL` → no-op |
| `wp-config-local.php` seed (contains prod URL as a literal) | inert | never `include`d on prod; prod's `wp-config.php` is hand-written or templated by deploy, not seeded from this file |
| `STAGE_FILE_PROXY_URL` constant | never defined on prod | gated on `WP_ENVIRONMENT_TYPE !== 'production'`, which is also never set on prod |
| Plugin activation row in `wp_options` | deactivated in prod | re-activated locally via `post-import-db` hook after each pull |

**What does NOT deploy to prod:**

- `wp-config.php` — gitignored, only exists on dev machines after `ddev start` runs the pre-start copy
- `WP_ENVIRONMENT_TYPE` — only defined inside `wp-config-local.php`, which only lands on local
- `STAGE_FILE_PROXY_URL` — gated behind the env-type check, so even if it leaked into a committed file it wouldn't fire on prod

**Bottom line:** the design fails closed in three independent ways. An attacker (or an accidental commit of `wp-config.php`) would need to defeat all three — the env-type check, the constant gate, and the deactivated plugin row — before stage_file_proxy could make an outbound request from prod.

## Step 6 — Tell the user what's next

```
ddev restart
ddev pull <environment-name>
```

`ddev restart` triggers the new post-start hook so `ddev auth ssh` runs once and loads their keys for the session. On a fresh clone it will also run the `pre-start` hook that seeds `wp-config.php` from `wp-config-local.php` (WordPress), or the `post-start` hook that seeds `settings.local.php` from `default.settings.local.php` (Drupal).

If the user chose to proceed with the `settings.local.php` bootstrap despite `settings.php` being gitignored (Step 4d.1, option 1), restate the manual deployment requirement here so it's the last thing they see: every other environment needs `settings.php` hand-edited (or templated by deploy tooling) to uncomment the `settings.local.php` include block, or the bootstrap silently does nothing there.

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
