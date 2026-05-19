# AGENTS.md

Guidance for AI coding agents working in this repository. Human contributors: this also doubles as a contributing guide.

## What this repo is

A [Claude Code plugin marketplace](https://code.claude.com/docs/en/plugin-marketplaces). Each top-level subdirectory is a standalone plugin that bundles one (occasionally more than one) skill — and, in `timesheet`'s case, a Claude Code hook. The marketplace manifest at `.claude-plugin/marketplace.json` lists every plugin.

```
<plugin-name>/
├── .claude-plugin/
│   └── plugin.json          # name, version, description, author
├── skills/
│   └── <skill-name>/
│       ├── SKILL.md         # the prompt that activates the skill
│       └── ...assets        # templates, scripts referenced by SKILL.md
├── hooks/                   # (timesheet only) hooks.json + scripts
└── scripts/                 # (timesheet only) one-time setup helpers
```

## Three-remote push convention

The repo has three remotes. **Every push must go to all three.** The marketplace is mirrored across them; teammates may pull from any of them.

| Remote   | URL                                          | Purpose                       |
|----------|----------------------------------------------|-------------------------------|
| `origin` | `gitlab:mark.labrecque/ai-skills`            | Personal canonical            |
| `ab`     | `gitlab-ab:mark/ai-skills`                   | Affinity Bridge mirror        |
| `github` | `github:marklabrecque-ab/ai-skills`          | Public GitHub mirror          |

After a commit, push the same ref to each:

```bash
git push origin main
git push ab main
git push github main
```

If any of the three pushes fails, surface it — don't quietly leave the mirrors out of sync.

## **MANDATORY**: bump versions on every push

**Every push must include a version bump in `.claude-plugin/plugin.json` for every plugin whose files were touched in that push.** This is non-negotiable. The marketplace has no other mechanism to signal "this plugin changed" to consumers; without the bump, `/plugin update` is a no-op and downstream installs stay frozen on the prior version.

### When to bump

If the diff between the last pushed commit and the commit you're about to push includes **any** change under `<plugin-name>/` — SKILL.md prose, templates, scripts, hook config, even `plugin.json` itself — then `<plugin-name>/.claude-plugin/plugin.json`'s `version` field must be higher than it was on the previous push.

The bump must land **in the same push** as the change, ideally in the same commit. Don't ship "I'll bump it next time" — the next push will touch different files and the version will still be stale.

### How to bump (SemVer)

| Change kind | Bump |
|---|---|
| Typo fix, doc-only clarification, comment tweak, internal refactor with no behavior change | **patch** (`0.1.0` → `0.1.1`) |
| New trigger keyword, new optional step, new template, new behavior that's backwards-compatible | **minor** (`0.1.0` → `0.2.0`) |
| Removed step, renamed required template, changed user-facing prompt flow, anything that could break existing users mid-session | **major** (`0.1.0` → `1.0.0`) |

When in doubt, **prefer a higher bump**. The cost of an over-bump is zero; the cost of an under-bump is consumers missing real changes.

### Multi-plugin commits

If a single commit touches files under two plugins (e.g. `ddev-setup/` and `composer-changelog/`), **both** `plugin.json` versions must be bumped in that commit. The bump in plugin A does not cover changes in plugin B.

### Files that DON'T require a bump

Only the following changes are exempt:
- Root-level `README.md`, `AGENTS.md`, `CLAUDE.md`, `.gitignore`, `.editorconfig`
- `.claude-plugin/marketplace.json` (the marketplace manifest itself — bumping it is meaningless since it has no version field)
- `docs/` at the repo root

If you find yourself wanting to add another exemption, push back on the request first — almost every other "trivial" change still ships to users and should be versioned.

### Pre-push check

Before pushing, run a sanity check. From the repo root:

```bash
# List plugins changed since the last pushed commit, and the current version of each
git diff --name-only @{push}..HEAD \
  | awk -F/ '$1 != "" && $1 !~ /^(\.|docs|README|AGENTS|CLAUDE)/ {print $1}' \
  | sort -u \
  | while read plugin; do
      [ -f "$plugin/.claude-plugin/plugin.json" ] || continue
      echo "=== $plugin ==="
      git show @{push}:"$plugin/.claude-plugin/plugin.json" 2>/dev/null | grep '"version"'
      grep '"version"' "$plugin/.claude-plugin/plugin.json"
    done
```

For every plugin listed, the second `version` line must be higher than the first. If it isn't, bump it before pushing.

## Commit conventions

- **Conventional commits**: `feat(<plugin>): ...`, `fix(<plugin>): ...`, `chore(<plugin>): ...`, `docs(<plugin>): ...`. Scope to the plugin name where applicable.
- One-line subject preferred; body only for non-obvious context.
- Group related work in a single commit; split unrelated work across separate commits.
- **Never** use `Co-Authored-By: Claude` lines.
- **Never** merge or rebase without explicit user request.
- **Never** push to remotes without explicit user request (the user typically says "push" or "bag and tag").

## Skill authoring conventions

- Each skill's `SKILL.md` starts with YAML frontmatter (`name`, `description`). The `description` is what Claude uses to decide whether to trigger the skill — make it specific, include trigger phrases, and re-test triggering after non-trivial edits.
- Templates that the skill writes into user projects live in `skills/<skill-name>/templates/`. Reference them via `~/.claude/skills/<skill-name>/templates/...` in `SKILL.md` (Claude resolves `~` to the user's home).
- Don't write `#ddev-generated` sentinels into files the skill ships; that comment tells DDEV the file is safe to overwrite, which is the opposite of what we want for hand-tuned configs.

## Tooling expectations

- **EditorConfig**: `.editorconfig` rules are authoritative. Default 2-space indentation everywhere except Python (4 spaces, PEP 8). Never use tabs.
- **Python**: don't fight `ruff format` / `black` defaults.
- **YAML / JSON / Markdown**: 2-space indent, LF line endings, trailing newline.

## Special cases

### `affinity-clone` is symlinked, not vendored

The `affinity-clone` skill lives in the Groundwork repo at `~/Projects/groundwork/skills/affinity-clone/` and is symlinked into `~/.claude/skills/` for the user's personal install. **It is not part of this marketplace.** Don't add it to `.claude-plugin/marketplace.json` and don't create a `~/skills/affinity-clone/` directory.

### `timesheet`'s post-commit hook is destructive-adjacent

The `timesheet` plugin ships a `post-commit` git hook (installed to `~/.config/git/hooks/post-commit`) that logs every commit into `~/daily_reports/{YYYY-MM-DD-Day}.md`. If you touch the hook or anything it parses (remote URL formats, regex, `sed`/`grep`/`awk` invocations), **end-to-end test it before pushing**:

1. Make a throwaway commit in any repo.
2. Verify a fresh entry appears in `~/daily_reports/<today>.md`.

`bash -n` is not sufficient — BSD/GNU tool differences bite at runtime, and `set -euo pipefail` can silently abort the hook before it writes. A previous "safe" tweak (PCRE `+?` in BSD sed) silently lost two full days of commit history.

## Glossary

- **DDEV** — local development environment manager that wraps Docker Compose; used by `ddev-setup`, `composer-changelog`, `screenshot-skill-init`, `wp-maintenance-tools`.
- **SemVer** — Semantic Versioning (`MAJOR.MINOR.PATCH`); see [semver.org](https://semver.org).
- **stage_file_proxy** — Drupal contrib module that fetches missing files from a configured origin on first request; used by `ddev-setup` as the default Drupal files-pull strategy.
