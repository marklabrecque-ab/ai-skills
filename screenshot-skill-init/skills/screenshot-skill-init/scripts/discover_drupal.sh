#!/usr/bin/env bash
# Discover pages worth screenshotting in a Drupal site.
#
# Three sources, in this order:
#   1. Menu tree (recursive) — default menu: "main"
#   2. System pages (login, 404, search if enabled, sitemap if enabled)
#   3. Oldest published node per content type (one example per bundle)
#
# Output: JSON array of {name, path, source} to stdout.
#
# Usage: discover_drupal.sh [--menu NAME] [--no-system-pages] [--no-content-types]
#
# Examples:
#   discover_drupal.sh
#   discover_drupal.sh --menu footer
#   discover_drupal.sh --no-content-types       # menu + system only, no node sampling
#
# List available menus:
#   ddev drush ev "print_r(array_keys(\Drupal::entityTypeManager()->getStorage('menu')->loadMultiple()));"
#
# Requires: ddev running, drush inside container.

set -euo pipefail

MENU="main"
INCLUDE_SYSTEM=true
INCLUDE_TYPES=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --menu)
      MENU="$2"; shift 2 ;;
    --no-system-pages)
      INCLUDE_SYSTEM=false; shift ;;
    --no-content-types)
      INCLUDE_TYPES=false; shift ;;
    -h|--help)
      sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//;/^set -euo/d'
      exit 0 ;;
    --*)
      echo "Unknown option: $1" >&2; exit 2 ;;
    *)
      # Back-compat: a single bare positional is treated as the menu name.
      MENU="$1"; shift ;;
  esac
done

# PHP heredoc executed inside the web container via `drush ev`.
# Bash expands ${MENU}, ${INCLUDE_SYSTEM}, ${INCLUDE_TYPES}; PHP variables
# are escaped with \$.
ddev drush ev "
\$out = [];

// --- 1. Menu tree (recursive) ---
\$params = new \Drupal\Core\Menu\MenuTreeParameters();
\$tree = \Drupal::menuTree()->load('${MENU}', \$params);

\$walk = function (\$branch) use (&\$walk, &\$out) {
  foreach (\$branch as \$el) {
    if (!\$el->link) continue;
    \$link = \$el->link;
    \$url = \$link->getUrlObject();
    \$route = \$url->isRouted() ? \$url->getRouteName() : '';
    // Skip <nolink> / <button> placeholders — they're not navigable URLs.
    if (!in_array(\$route, ['<nolink>', '<button>'], TRUE)) {
      try {
        \$path = \$url->isRouted() ? \$url->toString() : \$url->getUri();
        \$out[] = ['title' => \$link->getTitle(), 'path' => \$path, 'source' => 'menu'];
      } catch (\Exception \$e) {}
    }
    if (!empty(\$el->subtree)) {
      \$walk(\$el->subtree);
    }
  }
};
\$walk(\$tree);

// --- 2. System pages ---
if (${INCLUDE_SYSTEM}) {
  \$mh = \Drupal::moduleHandler();
  \$out[] = ['title' => 'Login', 'path' => '/user/login', 'source' => 'system'];
  \$out[] = ['title' => '404', 'path' => '/this-page-intentionally-does-not-exist', 'source' => 'system'];
  if (\$mh->moduleExists('search')) {
    \$out[] = ['title' => 'Search', 'path' => '/search', 'source' => 'system'];
  }
  if (\$mh->moduleExists('simple_sitemap') || \$mh->moduleExists('xmlsitemap')) {
    \$out[] = ['title' => 'Sitemap', 'path' => '/sitemap.xml', 'source' => 'system'];
  }
}

// --- 3. Oldest published node per content type ---
if (${INCLUDE_TYPES}) {
  \$node_def = \Drupal::entityTypeManager()->getDefinition('node');
  if (\$node_def && \$node_def->hasLinkTemplate('canonical')) {
    // Bundles to skip — administrative / non-canonical / typically uninteresting.
    \$skip = ['webform'];
    \$types = \Drupal::entityTypeManager()->getStorage('node_type')->loadMultiple();
    foreach (\$types as \$type) {
      \$tid = \$type->id();
      if (in_array(\$tid, \$skip, TRUE)) continue;
      \$nids = \Drupal::entityQuery('node')
        ->condition('type', \$tid)
        ->condition('status', 1)
        ->sort('created', 'ASC')
        ->range(0, 1)
        ->accessCheck(TRUE)
        ->execute();
      if (empty(\$nids)) continue;
      \$nid = reset(\$nids);
      \$node = \Drupal::entityTypeManager()->getStorage('node')->load(\$nid);
      if (!\$node) continue;
      try {
        \$path = \$node->toUrl()->toString();
        \$out[] = [
          'title' => \$type->label() . ': ' . \$node->label(),
          'path' => \$path,
          'source' => 'type:' . \$tid,
        ];
      } catch (\Exception \$e) {}
    }
  }
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
  # Strip scheme/host if drush returned an absolute URL.
  if "://" in path:
    path = urlparse(path).path or "/"
  if not path.startswith("/"):
    path = "/" + path
  if path in seen:
    continue
  seen.add(path)
  slug = re.sub(r"[^a-z0-9]+", "-", item["title"].lower()).strip("-") or f"item-{i}"
  out.append({
    "name": f"{i:02d}-{slug}",
    "path": path,
    "source": item.get("source", "menu"),
  })
  i += 1
json.dump(out, sys.stdout, indent=2)
sys.stdout.write("\n")
'
