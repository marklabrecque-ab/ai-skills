# test-marketplace

A Claude Code [plugin marketplace](https://code.claude.com/docs/en/plugin-marketplaces). Each subdirectory is a standalone plugin that wraps one skill (and, in `timesheet`'s case, a Claude Code hook).

## Add this marketplace

```bash
# In Claude Code
/plugin marketplace add <git-url-or-local-path>
/plugin install <plugin-name>@test-marketplace
```

## Plugins

### [composer-changelog](composer-changelog/)
Analyzes a `composer.lock` diff for Drupal projects, fetches release notes from Drupal.org for changed production dependencies, and produces a Markdown report highlighting breaking changes, deprecations, and security fixes. Always summarizes `drupal/core` changes when present.

### [ddev-setup](ddev-setup/)
Sets up a functional DDEV environment for Drupal or WordPress projects. Generates `.ddev/providers/*.yaml` files for `ddev pull`, wires `ddev auth ssh` into `post-start`, and for WordPress bootstraps a committed `wp-config-local.php` + `wp-config-override.php` pair so fresh clones boot cleanly. Auto-detects the CMS.

### [screenshot-skill-init](screenshot-skill-init/)
Generator skill. Scaffolds a pair of project-specific screenshot + compare skills into the current project's `.claude/skills/` so visual regression testing travels with the repo. Detects WordPress/Drupal/DDEV, discovers primary-nav pages via `wp-cli` or `drush`, and supports authenticated staging targets. Generated skill contents credit to Dale McGladdery (original LEAF skills).

### [timesheet](timesheet/)
Fills out a Harvest timesheet from daily log files. Also installs a `PostToolUse` hook that appends each `git commit` to today's daily report in `~/daily_reports/`. After install, run `timesheet/scripts/setup.sh` once to scaffold the shared config directory at `~/daily_reports/meta/`.

### [value-estimates](value-estimates/)
Generates value-based estimate reports — pulls tickets delivered in a date range from daily reports, cross-references each with its GitLab issue for an effort estimate, and compares against Harvest actuals. Shares config with `timesheet` (`~/daily_reports/meta/`).

## Plugin layout

```
<plugin-name>/
├── .claude-plugin/
│   └── plugin.json
├── skills/
│   └── <skill-name>/
│       ├── SKILL.md
│       └── ...assets
├── hooks/                 # (timesheet only) hooks.json + scripts
└── scripts/               # (timesheet only) one-time setup helpers
```

The repo root carries `.claude-plugin/marketplace.json`, which lists all plugins above.
