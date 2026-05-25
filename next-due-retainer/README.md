# next-due-retainer

A Claude Code skill that picks up the next due retainer ticket from a
GitLab group, assigns it to you, labels it **In Progress**, and clones the
associated repo locally if it isn't already on disk.

It's currently scoped to Affinity Bridge's self-hosted GitLab
(`git.affinitybridge.com`) and the **Retainers and Maintenance** group, but
the per-user bits (who "you" are, where repos get cloned) are configurable
via environment variables so the skill can be shared across the team.

## What it does

When triggered (e.g. "what's the next retainer?", "pick up the next
retainer", "start the next retainer"), the skill:

1. Pulls open issues from the **Retainers and Maintenance** group in
   GitLab, ordered by due date.
2. Picks the next one using this priority:
   - **First:** the earliest-due issue already assigned to you.
   - **Otherwise:** the earliest-due issue that is unassigned **and** not
     yet labelled `In Progress`.
3. Excludes the `mainwp` project from the pool.
4. Checks the three most recent (non-system) comments. If any was posted
   *after* the issue's due date, the issue is flagged as **needs review**
   and the link to the late comment is surfaced.
5. **Asks you to confirm** before making any change. Nothing is written
   until you say yes.
6. On confirmation: assigns the ticket to you and adds the
   `In Progress` label.
7. Reads the issue description for a `Repo:` or `Repository:` pointer.
   If found:
   - If the repo is already cloned under your clone directory, verifies
     the `origin` remote matches.
   - If not, clones it from `git@gitlab-ab:<owner>/<repo>.git` into your
     clone directory.
8. Prepares the working branch in the repo: checks out `main`,
   fast-forwards it against `origin/main`, then creates a fresh
   `retainer-update` branch off it.
9. If the repo has a `.ddev/` directory, runs `ddev start` followed by
   `ddev pull prod` to boot a local environment with prod data. Repos
   without DDEV skip this step.

## Prerequisites

- **`glab` CLI**, authenticated against the target GitLab host.
  Verify with:

  ```bash
  glab auth status
  ```

- **SSH access** to GitLab via the `gitlab-ab` host alias (used for
  cloning). Your `~/.ssh/config` should have an entry like:

  ```sshconfig
  Host gitlab-ab
      HostName git.affinitybridge.com
      User git
      Port 22222
      IdentityFile ~/.ssh/id_ed25519   # whichever key you use
  ```

- **Claude Code** with this plugin installed from the marketplace.

## Configuration

The skill resolves three things at runtime — none of them hardcoded —
so teammates can share the skill without stepping on each other's
identity or filesystem layout.

| Env var | Purpose | Default |
|---|---|---|
| `NEXT_DUE_RETAINER_USER` | GitLab username used for filtering "assigned to me" and for the assignment write. | The currently authenticated `glab` user (`glab api user → .username`). |
| `NEXT_DUE_RETAINER_CLONE_DIR` | Base directory where retainer repos are cloned and looked up. `~` and `$HOME` are expanded. | `~/Projects/retainers` |

Set them in your shell rc file (`~/.zshrc`, `~/.bashrc`, etc.) so they're
present for every Claude Code session. Example:

```bash
# next-due-retainer
export NEXT_DUE_RETAINER_CLONE_DIR="$HOME/work/retainers"
# Optional — only set if you want to filter as a different user than
# the one `glab` is authed as:
# export NEXT_DUE_RETAINER_USER="someone-else"
```

After editing, restart your shell (or `source` the file) **and** restart
Claude Code so the new env reaches the tool process.

### Verifying your configuration

```bash
echo "user:      ${NEXT_DUE_RETAINER_USER:-<auto via glab api user>}"
echo "clone dir: ${NEXT_DUE_RETAINER_CLONE_DIR:-$HOME/Projects/retainers}"
glab api user --jq '.username'
```

The first two lines show what the skill will use; the last shows what
`glab` thinks you are. They should agree (or `NEXT_DUE_RETAINER_USER`
should be the override you intend).

## Safety guarantees

- **No writes without confirmation.** The skill always shows you the
  candidate ticket (title, link, due date, planned changes, and any
  "needs review" flags) and waits for an explicit approval before
  calling any `PUT` / `POST` endpoint.
- **No remote rewrites.** If a repo is already present locally but its
  `origin` doesn't match the ticket, the mismatch is surfaced — the
  skill will not rewrite remotes for you.
- **No guessing.** If the issue description has no `Repo:` /
  `Repository:` pointer, the skill stops and tells you instead of
  picking a likely-looking repo.
- **No destructive git.** When preparing the `retainer-update` branch,
  the skill uses `--ff-only` pulls and refuses to overwrite an existing
  `retainer-update` branch — it surfaces the situation to you and waits
  for guidance instead of `stash`/`reset`/`--force`-ing.
- **Scope-limited mutation.** Only `assignee_ids` and `add_labels` are
  ever sent to GitLab. Due date, milestone, description, etc. are
  untouched.

## Troubleshooting

- **"`glab` not authenticated" / 401 errors:** run `glab auth login`
  against `git.affinitybridge.com`.
- **Skill picks the wrong user:** check `NEXT_DUE_RETAINER_USER` (if
  set) and `glab api user --jq '.username'`. Whichever the skill
  resolves to is what it will assign the ticket to.
- **Clone target is wrong:** check `NEXT_DUE_RETAINER_CLONE_DIR`. The
  default is `~/Projects/retainers`, not `~/Projects`.
- **SSH clone fails:** confirm `ssh -T gitlab-ab` works. If you don't
  have the `gitlab-ab` Host alias in `~/.ssh/config`, add one (see
  *Prerequisites*).
- **"In Progress" label not applied:** the label name is
  case-sensitive on GitLab. If your group renames it, the skill needs
  the new name; open an issue / PR to update the SKILL.md.

## Files

```
next-due-retainer/
├── .claude-plugin/
│   └── plugin.json
├── skills/
│   └── next-due-retainer/
│       └── SKILL.md        ← the actual instructions the agent reads
└── README.md               ← this file
```

The behavior lives in `skills/next-due-retainer/SKILL.md`. If you want
to change the selection algorithm, the label name, or which projects
are excluded, that's the file to edit.
