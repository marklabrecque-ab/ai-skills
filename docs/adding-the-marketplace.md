# Adding the `marks-affinitybridge-plugins` marketplace to Claude Code

This repo doubles as a [Claude Code plugin marketplace](https://docs.claude.com/en/docs/claude-code/plugin-marketplaces). Once you add it, every plugin listed in `.claude-plugin/marketplace.json` is one `/plugin install` away.

## Prerequisites

- Claude Code CLI installed (`claude --version` should print a version).
- SSH access to the GitLab repo (or use HTTPS — see below).

## 1. Add the marketplace

Inside any Claude Code session, run:

```
/plugin marketplace add git@git.affinitybridge.com:mark/ai-skills.git
```

Claude clones the repo into its plugin cache and registers the marketplace under the name declared in `.claude-plugin/marketplace.json` — `marks-affinitybridge-plugins`.

> **Note:** If you previously added this marketplace under its old name (`test-marketplace`), remove it first:
>
> ```
> /plugin marketplace remove test-marketplace
> ```

### Alternative sources

| Remote   | URL                                                       |
|----------|-----------------------------------------------------------|
| GitLab (canonical) | `git@git.affinitybridge.com:mark/ai-skills.git` |
| GitLab.com (mirror) | `git@gitlab.com:mark.labrecque/ai-skills.git`  |
| GitHub (mirror)     | `git@github.com:marklabrecque-ab/ai-skills.git` |

All three are kept in sync. Pick whichever you have credentials for. HTTPS URLs work too if you don't have SSH set up.

## 2. Browse and install plugins

List what's available:

```
/plugin marketplace list marks-affinitybridge-plugins
```

Install a specific plugin:

```
/plugin install <plugin-name>@marks-affinitybridge-plugins
```

For example:

```
/plugin install timesheet@marks-affinitybridge-plugins
/plugin install ddev-setup@marks-affinitybridge-plugins
/plugin install composer-changelog@marks-affinitybridge-plugins
```

## 3. Keep the marketplace up to date

Pull the latest plugin definitions:

```
/plugin marketplace update marks-affinitybridge-plugins
```

Then update any installed plugins:

```
/plugin update <plugin-name>
```

## 4. Reload plugins after changes

Claude Code loads plugin definitions (commands, skills, hooks, MCP servers) at session start. If you install, update, or uninstall a plugin **mid-session**, the new state won't take effect until you reload:

```
/plugins-reload
```

Run this any time:

- You just ran `/plugin install` or `/plugin update` and the new commands/skills aren't showing up.
- You just ran `/plugin marketplace update` and want the updated plugin definitions to apply.
- You edited a plugin's files locally (e.g. iterating on a `SKILL.md` or command in this repo) and want Claude to pick up the changes without restarting.

You'll likely run this more often than you'd expect — it's the most common gotcha for new users. If a plugin "isn't working," reload first before debugging anything else.

## 5. Removing things

Uninstall a single plugin:

```
/plugin uninstall <plugin-name>
```

Remove the whole marketplace (uninstalls everything from it):

```
/plugin marketplace remove marks-affinitybridge-plugins
```

## Current plugins

See [`marketplace.json`](../.claude-plugin/marketplace.json) for the authoritative list. At time of writing:

- **agent-helper** — scaffold a project-level set of self-improving Claude Code agents.
- **claude-context-management** — utilities for managing Claude Code's local context.
- **composer-changelog** — analyze `composer.lock` diffs for Drupal projects and produce a changelog report.
- **ddev-setup** — set up a DDEV environment for Drupal or WordPress projects.
- **next-due-retainer** — pick up the next due retainer ticket from the Affinity Bridge GitLab "Retainers and Maintenance" group.
- **screenshot-skill-init** — scaffold project-specific screenshot + compare skills for visual regression.
- **timesheet** — fill out Harvest timesheets from daily log files.
- **value-estimates** — generate value-based estimate reports comparing GitLab estimates to Harvest actuals.
- **wp-maintenance-tools** — maintenance skills for WordPress projects (e.g. pre-update plugin risk reports).

## Troubleshooting

- **`/plugin` command not found** — your Claude Code CLI is too old. Upgrade with `npm install -g @anthropic-ai/claude-code` (or your installer of choice).
- **Permission denied (publickey)** — your SSH key isn't registered with the host you're cloning from. Either add your key or switch to an HTTPS URL.
- **Marketplace name shows as `test-marketplace`** — you added it before the rename. Run `/plugin marketplace remove test-marketplace` and re-add with the command above.
