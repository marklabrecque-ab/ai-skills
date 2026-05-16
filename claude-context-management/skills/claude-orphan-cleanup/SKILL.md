---
name: claude-orphan-cleanup
description: Find and remove orphaned project-scoped Claude data folders under `~/.claude/projects/` whose original source directory no longer exists on disk. Use this skill whenever the user mentions cleaning up orphaned Claude project data, stale `.claude/projects` folders, reclaiming disk from old session/memory data, or asks "which Claude project folders no longer have a source directory" — even if they don't use the word "orphan". Also trigger when retiring a project and the user wants to mothball or remove its Claude-side traces.
---

# Claude orphan-data cleanup

`~/.claude/projects/<encoded-cwd>/` holds session JSONL files and project-scoped memory for every directory Claude Code has ever been invoked from. When the source directory is deleted (or moved, or archived), the corresponding data folder stays on disk forever — it just becomes invisible to future sessions because no cwd will ever match it again.

This skill finds those orphans and offers to delete them.

## Workflow

1. **Run the detection script** to list every project folder with its status:

   ```bash
   python3 "${CLAUDE_PLUGIN_ROOT}/skills/claude-orphan-cleanup/scripts/find_orphans.py"
   ```

   Output is TSV with columns `status`, `size`, `encoded_name`, `cwd_or_reason`. Status is one of:

   - `orphan` — the recorded cwd does not exist (or it's a worktree path whose parent project is gone). Safe to delete.
   - `live` — the cwd exists; keep.
   - `unknown` — no readable session JSONL was found, so the script can't determine the original cwd. Needs manual review (often these are memory-only folders or aborted sessions).

2. **Present the orphans to the user as a table**, sorted by size descending. The pre-delete report MUST include a clearly labelled total of reclaimable disk space — sum the `size_bytes` column across all orphan rows and show it formatted human-readably (the script's stderr summary already computes this; you can read it directly or re-sum from the TSV). The user has called this out as required, not optional. Group worktree-orphans separately from project-orphans — they're often larger and less obviously tied to retired projects, and the user usually wants to eyeball them first.

3. **Handle `unknown` entries by asking** rather than guessing. List them with their encoded names and let the user say which (if any) to delete. Decoding the encoded name (replacing `-` with `/`) is unreliable because real paths can contain dashes — surface the ambiguity instead of acting on it.

4. **Prompt for deletion explicitly.** Show the user the orphan list + total reclaimable space and confirm before running `rm -rf`. Default to no deletion until the user says yes; never delete an `unknown` or `live` row.

5. **Delete in one batch** once confirmed, then re-run the detection script and report actual space reclaimed (pre-delete total vs post-delete remaining) so the user gets a clean before/after.

## Why the cwd comes from JSONL, not the folder name

The folder name is a path with `/` replaced by `-`, but paths can themselves contain `-` (e.g. `/Users/mark/Projects/cupe-bc`). Decoding `-Users-mark-Projects-cupe-bc` is ambiguous — could be `/Users/mark/Projects/cupe/bc` or `/Users/mark/Projects/cupe-bc`. Session JSONL files record the actual `cwd` field, so reading from them is unambiguous.

The trade-off: folders with no session files (memory-only, or sessions that never wrote a line) come back as `unknown`. That's intentional — guessing is worse than asking.

## Worktree handling

Worktree cwds typically live at `<parent>/.claude/worktrees/<name>`. The script treats a worktree-data folder as orphaned whenever the parent project path is missing, regardless of whether the recorded worktree path itself resolves. This matches the user's preference: if a project is gone, its worktree-data should go with it.

## What this skill does NOT do

- It does not touch the user-scoped memory at `~/.claude/projects/-Users-mark--claude/memory/`. That's the user's global Claude memory home, not a per-project folder; cleaning that up is a different (manual) task.
- It does not modify or back up data before deleting — the user is expected to be sure. The script is read-only; deletion happens via `rm -rf` invoked by Claude after explicit user confirmation.
- It does not touch the actual source folders under `~/Projects/` — only the Claude-side data shadow.
