# Skills

Personal collection of Claude Code skills. Each subdirectory is a self-contained skill with its own `SKILL.md`.

## Skills

### [composer-changelog](composer-changelog/)
Analyzes a `composer.lock` diff for Drupal projects, fetches release notes from Drupal.org for changed production dependencies, and produces a Markdown report highlighting breaking changes, deprecations, and security fixes. Always summarizes `drupal/core` changes when present.

### [ddev-setup](ddev-setup/)
Sets up a functional DDEV environment for Drupal or WordPress projects. Generates `.ddev/providers/*.yaml` files for `ddev pull`, wires `ddev auth ssh` into `post-start`, and for WordPress bootstraps a committed `wp-config-local.php` + `wp-config-override.php` pair so fresh clones boot cleanly. Auto-detects the CMS.

### [screenshot-skill-init](screenshot-skill-init/)
Generator skill. Scaffolds a pair of project-specific screenshot + compare skills into the current project's `.claude/skills/` so visual regression testing travels with the repo. Detects WordPress/Drupal/DDEV, discovers primary-nav pages via `wp-cli` or `drush`, and supports authenticated staging targets.

### [timesheet](timesheet/)
Fills out a Harvest timesheet from daily log files — parses work logs, maps entries to Harvest projects/tasks, and submits hours.

## Layout

```
<skill-name>/
├── SKILL.md          # Frontmatter (name, description) + instructions for Claude
├── templates/        # (optional) files the skill writes into projects
└── ...               # supporting scripts/data
```

The `description` field in each `SKILL.md` frontmatter is what determines when Claude Code auto-triggers the skill.
