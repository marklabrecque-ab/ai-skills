#!/usr/bin/env python3
"""
Render the screenshot + compare skill pair into a project's .claude/skills/.

Usage:
  render.py --slug leaf --project-name "LEAF" \\
            --targets targets.json --pages pages.json \\
            --out /path/to/project/.claude/skills/

Inputs:
  - targets.json: list of {name, url, self_signed?, auth_user_env?, auth_pass_env?}
  - pages.json:   list of {name, path}

Writes:
  <out>/screenshot-<slug>/SKILL.md
  <out>/screenshot-<slug>/pages.json
  <out>/screenshot-<slug>/scripts/screenshot.py
  <out>/compare-<slug>-screenshots/SKILL.md
  <out>/compare-<slug>-screenshots/scripts/compare.py

Template substitution is plain str.replace on these tokens:
  {{SLUG}}, {{PROJECT_NAME}}, {{TARGETS_JSON}}, {{TARGET_NAMES}}, {{DEFAULT_TARGET}}
"""

import argparse
import json
import shutil
from pathlib import Path

TEMPLATES_DIR = Path(__file__).resolve().parent.parent / 'templates'


def render_file(template_path: Path, out_path: Path, tokens: dict):
  text = template_path.read_text()
  for key, value in tokens.items():
    text = text.replace('{{' + key + '}}', value)
  out_path.parent.mkdir(parents=True, exist_ok=True)
  out_path.write_text(text)
  # Preserve executable bit for scripts
  if template_path.suffix == '.py' or template_path.name.endswith('.py.tmpl'):
    out_path.chmod(0o755)


def main():
  p = argparse.ArgumentParser()
  p.add_argument('--slug', required=True)
  p.add_argument('--project-name', required=True)
  p.add_argument('--targets', required=True, help='Path to targets.json')
  p.add_argument('--pages', required=True, help='Path to pages.json')
  p.add_argument('--out', required=True, help='Project .claude/skills/ dir')
  args = p.parse_args()

  slug = args.slug
  out = Path(args.out).resolve()
  targets = json.loads(Path(args.targets).read_text())
  pages = json.loads(Path(args.pages).read_text())

  if not targets:
    raise SystemExit('targets.json must contain at least one target')
  if not pages:
    raise SystemExit('pages.json must contain at least one page')

  target_names = [t['name'] for t in targets]
  default_target = 'ddev' if 'ddev' in target_names else target_names[0]

  # Use pprint to emit a Python literal (True/False/None) rather than JSON
  # (true/false/null), so the substitution drops cleanly into Python source.
  import pprint
  targets_py = pprint.pformat(targets, indent=2, width=100, sort_dicts=False)

  tokens = {
    'SLUG': slug,
    'PROJECT_NAME': args.project_name,
    'TARGETS_JSON': targets_py,
    'TARGET_NAMES': ', '.join(f'`{n}`' for n in target_names),
    'DEFAULT_TARGET': default_target,
  }

  shot_dir = out / f'screenshot-{slug}'
  cmp_dir = out / f'compare-{slug}-screenshots'

  render_file(TEMPLATES_DIR / 'screenshot' / 'SKILL.md.tmpl',
              shot_dir / 'SKILL.md', tokens)
  render_file(TEMPLATES_DIR / 'screenshot' / 'scripts' / 'screenshot.py.tmpl',
              shot_dir / 'scripts' / 'screenshot.py', tokens)
  render_file(TEMPLATES_DIR / 'compare' / 'SKILL.md.tmpl',
              cmp_dir / 'SKILL.md', tokens)
  render_file(TEMPLATES_DIR / 'compare' / 'scripts' / 'compare.py.tmpl',
              cmp_dir / 'scripts' / 'compare.py', tokens)

  # pages.json lives in the screenshot skill; compare reads it via relative path
  (shot_dir / 'pages.json').write_text(json.dumps(pages, indent=2) + '\n')

  print(f'Wrote:')
  for path in [
    shot_dir / 'SKILL.md',
    shot_dir / 'pages.json',
    shot_dir / 'scripts' / 'screenshot.py',
    cmp_dir / 'SKILL.md',
    cmp_dir / 'scripts' / 'compare.py',
  ]:
    print(f'  {path}')


if __name__ == '__main__':
  main()
