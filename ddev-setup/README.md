# ddev-setup

Bring a Drupal or WordPress project to a functional DDEV state — provider YAML for `ddev pull`, SSH-agent wiring, and a CMS-appropriate local-config bootstrap so fresh clones boot cleanly.

## What it does

The skill detects the CMS (Drupal vs WordPress) from the codebase and produces four things:

1. **Provider file** — `.ddev/providers/<env>.yaml` so `ddev pull <env>` can sync database and user-uploaded files from a remote server. One per environment (`prod`, `stage`, `dev`, `cert`).
2. **`ddev auth ssh` post-start hook** — wired into `.ddev/config.yaml` so SSH keys load automatically on `ddev start`. No more `ddev auth ssh` before every pull.
3. **Local-config bootstrap:**
   - **WordPress** — commits a `wp-config-local.php` that DDEV copies into `wp-config.php` on first start (if missing), plus a `wp-config-override.php` that's included last in the cascade so `$table_prefix` and other per-project overrides win.
   - **Drupal** — commits a `default.settings.local.php` (seeded from a template with `stage_file_proxy` origin pre-filled), wires a `post-start` hook that copies it into the gitignored `settings.local.php`, and uncomments the include block in `settings.php`. Requires `settings.php` to be tracked in git; the skill loudly confirms if it's not.
4. **PII audit + database sanitization (required, both CMSes)** — after the first pull, the local database is analyzed for personally identifiable information (schema scan, known-table checklists, bounded data sampling — counts only, never values). Findings and per-category decisions (truncate / anonymize / keep) are recorded in a committed `docs/pii-audit.md`, and a project-specific `.ddev/scripts/sanitize-db.sh` (Drupal: `drush sql:sanitize` base layer; WordPress: wp-cli user/comment anonymization base layer) is wired into a `post-import-db` hook so every future pull is sanitized automatically. The script is gated on `IS_DDEV_PROJECT` so it can never run outside a DDEV container.

## Prerequisites

- DDEV installed.
- An SSH alias or credentials for the remote environment (a `~/.ssh/config` alias alone isn't enough — the provider file needs explicit `*HOST*` and `*USER*` env vars).
- The remote path (composer/project root on the server).

## How to use

Trigger by:

- "Set up `ddev pull` on this project"
- "Add a prod/stage/dev/cert environment"
- "The provider is missing/broken"
- "Bootstrap wp-config for a fresh clone"
- "Set up Drupal's settings.local.php on a fresh clone"
- "Sanitize/anonymize the local database" or "audit the pulled database for PII"

The skill will ask for SSH user/host/port (defaults to **22222**), remote path, and the environment name.

## Safety

`.ddev/providers/<env>.yaml` files are never overwritten. If a target file exists, the skill stops, shows the existing contents, and asks how to proceed. Production providers in particular often contain hand-tuned settings the template can't reproduce.
