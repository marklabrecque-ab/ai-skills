#!/usr/bin/env bash
# Discover primary-nav pages in a Drupal site via ddev + drush.
# Prints JSON: [{"name": "00-home", "path": "/"}, ...] to stdout.
#
# Usage: discover_drupal.sh [menu-name]
#   menu-name defaults to "main" — common values: main, account, footer.
#   List what's available with:
#     ddev drush ev "print_r(array_keys(\Drupal::entityTypeManager()->getStorage('menu')->loadMultiple()));"
#
# Requires: ddev running, drush inside container.

set -euo pipefail

MENU="${1:-main}"

# Use drush to dump the menu tree as JSON. We reach into the menu link tree
# service; this is stable across Drupal 9/10/11.
ddev drush ev "
\$tree = \Drupal::menuTree()->load('$MENU', new \Drupal\Core\Menu\MenuTreeParameters());
\$out = [];
foreach (\$tree as \$el) {
  \$link = \$el->link;
  \$title = \$link->getTitle();
  \$url = \$link->getUrlObject();
  if (\$url->isRouted()) {
    try { \$path = \$url->toString(); } catch (\Exception \$e) { continue; }
  } else {
    \$path = \$url->getUri();
  }
  \$out[] = ['title' => \$title, 'path' => \$path];
}
echo json_encode(\$out);
" 2>/dev/null \
  | python3 -c '
import json, re, sys
from urllib.parse import urlparse

raw = sys.stdin.read().strip()
items = json.loads(raw) if raw else []
seen = set()
out = []
i = 0
for item in items:
  path = item["path"]
  # Strip scheme/host if drush returned an absolute URL
  if "://" in path:
    path = urlparse(path).path or "/"
  if not path.startswith("/"):
    path = "/" + path
  if path in seen:
    continue
  seen.add(path)
  slug = re.sub(r"[^a-z0-9]+", "-", item["title"].lower()).strip("-") or f"item-{i}"
  out.append({"name": f"{i:02d}-{slug}", "path": path})
  i += 1
json.dump(out, sys.stdout, indent=2)
sys.stdout.write("\n")
'
