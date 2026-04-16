---
name: ddev-provider
description: Creates DDEV provider YAML files (.ddev/providers/*.yaml) for pulling databases and files from remote servers. Use when the user wants to set up `ddev pull`, add a new environment (prod/stage/dev/cert) to a DDEV project, configure database and files sync from a remote server, fix a missing or broken provider, or mentions needing a "DDEV provider". The skill detects the project's CMS (Drupal vs WordPress) from the codebase and selects the correct template — drush-based for Drupal, wp-cli-based for WordPress — then substitutes the connection details.
---

# DDEV Provider

Generate a `.ddev/providers/<name>.yaml` file so `ddev pull <name>` can sync a database and user-uploaded files from a remote server into the local DDEV environment. Templates live in `templates/` alongside this file.

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
| `wp-config.php`, `web/wp-config.php`, or `composer.json` contains `"roots/bedrock"` / `"johnpbloch/wordpress"` | WordPress | `templates/wordpress.yaml` |
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

**WordPress-specific:**
- `WP_CWD` — `web` for Bedrock (detected: `roots/bedrock` in composer.json), `.` for a standard WordPress layout.
- `UPLOADS_SUBPATH` — `web/wp-content/uploads` for Bedrock, `wp-content/uploads` for standard WP.

If the user only has an `~/.ssh/config` alias (e.g. `islandhealth-prod`) and no separate user/port/keyfile, warn them: `affinity-clone` requires both a `*HOST*` and a `*USER*` env var in the provider file. Either resolve the alias (`ssh -G <alias> | grep -E '^(user|hostname|port|identityfile)'`) and fill the fields, or leave it — but `affinity-clone`'s preflight parser will refuse the file.

## Step 3 — Write the file

1. Read the matching template. Templates are located at `~/.claude/skills/ddev-provider/templates/` (resolve `~` to the user's home directory for an absolute path).
2. Replace every `{{PLACEHOLDER}}` token with the gathered value.
3. Write the result to `<project-root>/.ddev/providers/<environment-name>.yaml`.
4. Do NOT include the DDEV-generated sentinel comment (`#ddev-generated`) — that comment signals DDEV can overwrite the file. Custom providers must omit it.

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

## Step 5 — Tell the user what's next

```
ddev restart
ddev pull <environment-name>
```

`ddev restart` triggers the new post-start hook so `ddev auth ssh` runs once and loads their keys for the session.

## Notes on the template shape

- Both templates use `environment_variables` with `ssh_user` and `ssh_host` (lowercase). The `affinity-clone` script parses these case-insensitively but requires exactly one variable containing `HOST` and one containing `USER` — don't add a second (e.g. don't introduce a `remote_user` alongside `ssh_user`).
- Push commands are stubbed out with an "unsupported" message by default. This is deliberate: accidental `ddev push prod` is a disaster. Only enable pushes for non-production targets, and only if the user explicitly asks.
- `files_pull_command` uses rsync of the uploads/files directory. For large sites the user may prefer `stage_file_proxy` instead — in that case, replace the `files_pull_command` body with a no-op `echo` (see the islandhealth-style prod examples in the user's project checkouts).

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
