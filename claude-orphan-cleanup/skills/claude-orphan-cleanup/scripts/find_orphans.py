#!/usr/bin/env python3
"""
Find orphaned project-scoped data folders under ~/.claude/projects/.

A project folder is orphaned when the cwd it was created for no longer exists
on disk. The cwd is read from the first session JSONL file in the folder
(reliable) rather than decoded from the encoded folder name (ambiguous when
paths contain dashes).

Worktree-style data folders are orphaned whenever their parent project's path
is missing, even if the recorded worktree cwd technically still resolves —
this matches the user's preference that worktree-data should not outlive its
parent project.

Output: TSV to stdout with columns: status, size_human, size_bytes, encoded_name, cwd
  - status=orphan       — confirmed orphan; safe to delete
  - status=live         — cwd exists; keep
  - status=unknown      — no session JSONL to inspect; needs manual review

Summary on stderr reports total reclaimable space across all orphan rows.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

PROJECTS_DIR = Path.home() / ".claude" / "projects"
WORKTREE_MARKER = "/.claude/worktrees/"


def first_session_cwd(project_dir: Path) -> str | None:
    """Return the cwd recorded in any JSONL line, scanning files until found.

    JSONL files start with metadata records (last-prompt, permission-mode,
    bridge_status) that don't carry a cwd; the cwd appears once a real
    user/assistant message is logged. Scan every line, and try every file
    in the project dir before giving up.
    """
    for jsonl in sorted(project_dir.glob("*.jsonl")):
        try:
            with jsonl.open() as f:
                for line in f:
                    if not line.strip():
                        continue
                    try:
                        data = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    cwd = data.get("cwd")
                    if cwd:
                        return cwd
        except OSError:
            continue
    return None


def parent_of_worktree(cwd: str) -> str | None:
    """If cwd points inside a worktree, return the parent project path."""
    idx = cwd.find(WORKTREE_MARKER)
    if idx == -1:
        return None
    return cwd[:idx]


def folder_size_bytes(path: Path) -> int:
    """Sum the apparent size of every regular file under path."""
    total = 0
    for root, _dirs, files in os.walk(path, followlinks=False):
        for name in files:
            fp = os.path.join(root, name)
            try:
                total += os.lstat(fp).st_size
            except OSError:
                pass
    return total


def human_size(n: int) -> str:
    """Format bytes as a short human string (B, K, M, G, T)."""
    step = 1024.0
    for unit in ("B", "K", "M", "G", "T"):
        if n < step:
            return f"{n:.0f}{unit}" if unit == "B" else f"{n:.1f}{unit}"
        n /= step
    return f"{n:.1f}P"


def classify(project_dir: Path) -> tuple[str, str]:
    """Return (status, cwd_or_reason)."""
    cwd = first_session_cwd(project_dir)
    if cwd is None:
        return ("unknown", "(no readable session files)")

    parent = parent_of_worktree(cwd)
    if parent is not None and not os.path.isdir(parent):
        return ("orphan", f"{cwd}  (parent missing: {parent})")

    if not os.path.isdir(cwd):
        return ("orphan", cwd)

    return ("live", cwd)


def main() -> int:
    if not PROJECTS_DIR.is_dir():
        print(f"error: {PROJECTS_DIR} does not exist", file=sys.stderr)
        return 1

    rows = []
    for entry in sorted(PROJECTS_DIR.iterdir()):
        if not entry.is_dir():
            continue
        status, detail = classify(entry)
        size_b = folder_size_bytes(entry)
        rows.append((status, human_size(size_b), str(size_b), entry.name, detail))

    print("status\tsize_human\tsize_bytes\tencoded_name\tcwd_or_reason")
    for row in rows:
        print("\t".join(row))

    counts = {"orphan": 0, "live": 0, "unknown": 0}
    bytes_by_status = {"orphan": 0, "live": 0, "unknown": 0}
    for status, _h, size_b, _n, _d in rows:
        counts[status] = counts.get(status, 0) + 1
        bytes_by_status[status] = bytes_by_status.get(status, 0) + int(size_b)

    print(
        f"\nSummary: {counts['orphan']} orphan ({human_size(bytes_by_status['orphan'])} reclaimable), "
        f"{counts['live']} live ({human_size(bytes_by_status['live'])}), "
        f"{counts['unknown']} unknown ({human_size(bytes_by_status['unknown'])})",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
