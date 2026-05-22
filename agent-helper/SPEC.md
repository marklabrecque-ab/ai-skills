# agent-helper plugin — spec

Status: draft (pre-implementation)

## Purpose

Scaffold a project-level set of Claude Code agents into `.claude/agents/`
(committed to the repo) plus an optional development workflow guide. Agents
are designed to be **self-improving** via user-approved diffs: when they hit
recurring friction, they propose a patch to their own instructions instead of
working around the problem each time.

## Skill invocation

`/agent-helper` — runs inside a project. On invocation the skill detects:

- Git remote (GitHub vs GitLab) → picks `gh` vs `glab` and PR vs MR
  terminology. Honors the global rule: prefer the `origin` remote when more
  than one is present.
- Base branch (`develop` if it exists, else `main`) → confirmed with the user.
- Existing `.claude/agents/` → offers merge / skip / overwrite per file.

## Default agent roster

Four agents, written to `.claude/agents/`:

1. **planner.md** — decomposes a ticket into an implementation outline before
   the implementor starts. Reads the ticket from GitLab/GitHub, produces a
   short plan, makes no code changes.
2. **implementor.md** — owns steps 1–3 of the workflow. Branches off the base
   branch, implements, writes/runs tests, opens the MR/PR.
3. **tester.md** — focused on automated test authoring and green-CI
   verification. Distinct from implementor so the "did you actually test it"
   step is structural rather than optional.
   - Covers unit + integration tests by default.
   - Adds **Playwright** coverage when the feature is user-facing or has a
     behavioral flow worth exercising end-to-end. Skips Playwright for pure
     backend/library/internal changes.
   - Honors the user's global Playwright rules: headless by default,
     Chromium for MCP, `npx playwright` for CLI, scaffolds a self-contained
     `playwright.config.ts` if one isn't already committed.
4. **reviewer.md** — owns steps 5–6. Reviews the MR/PR, classifies feedback
   as must-fix / 5-min-fix / backlog-ticket, files backlog items in the
   **same forge and project the original ticket came from** (single source of
   truth), approves, but never merges.

At scaffold time the skill prompts: "Use this default roster, or customize?"
Customize lets the user drop/rename/add agents.

## Workflow document

Writes `.claude/WORKFLOW.md` (committed) describing:

1. Implementor pulls a ticket → branches `<ticket>-<slug>` off
   `<base-branch>`.
2. Implementor implements to completion.
3. Implementor adds automated tests and ensures everything runs green
   locally and in CI.
4. Implementor opens an MR/PR against `<base-branch>` and assigns the
   reviewer.
5. Reviewer triages feedback:
   - must-fix and 5-minute fixes go back to implementor on the same MR/PR;
   - everything else becomes new backlog tickets filed by the reviewer in
     the same forge/project, with a link back to the originating MR/PR.
6. Reviewer approves. **Does not merge.** Merge is a human decision unless
   the invoker explicitly opts in at scaffold time.

The skill prompts once: "Allow agents to auto-merge after approval?
(default: no)". If yes, the skill records that opt-in in `.claude/WORKFLOW.md`
and adds a corresponding instruction block to `reviewer.md`.

## Self-improvement protocol

Every scaffolded agent gets a shared footer section, roughly:

> **Self-improvement protocol.** If you hit the same friction twice in one
> session (auth failures, missing tooling, ambiguous instructions, repeated
> user corrections), stop working around it. Instead:
>
> 1. Propose a concrete patch to your own instructions file
>    (`.claude/agents/<name>.md`) as a unified diff.
> 2. Explain the trigger: what went wrong, and why the current instructions
>    didn't prevent it.
> 3. Wait for the user to approve before applying. Never edit yourself
>    silently.
> 4. After approval, apply the edit and continue the original task.
>
> Goal: suggest the unblock for *now* and the durable fix for *next time*.
> Don't paper over recurring problems.

## CLAUDE.md edits

The skill confirms with the user before touching `CLAUDE.md`. Edits are
**addition-only**: append a new section pointing at `.claude/WORKFLOW.md`
and the agent roster.

If existing instructions in `CLAUDE.md` conflict with the workflow (e.g. a
different branch model, a different review handoff), the skill **does not
edit the conflicting lines**. Instead it surfaces a diff-style suggestion
describing the conflict and a proposed amendment, and waits for explicit
approval before applying — same posture as the self-improvement protocol:
propose, don't overwrite.

## Files written into a project

```
.claude/
  agents/
    planner.md
    implementor.md
    tester.md
    reviewer.md
  WORKFLOW.md
```

Plus an addition-only section in the project's `CLAUDE.md` (created if
missing) pointing at `.claude/WORKFLOW.md`.

## Plugin layout in `~/skills/`

```
agent-helper/
  .claude-plugin/plugin.json
  skills/agent-helper/SKILL.md
  templates/
    planner.md
    implementor.md
    tester.md
    reviewer.md
    WORKFLOW.md
  SPEC.md
```

Marketplace entry added to `~/skills/.claude-plugin/marketplace.json`.

## Open questions

- None blocking. Tester scope, backlog routing, and CLAUDE.md edit posture
  are all resolved above.
