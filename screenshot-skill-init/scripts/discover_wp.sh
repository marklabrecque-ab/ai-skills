#!/usr/bin/env bash
# Discover primary-nav pages in a WordPress site via ddev + wp-cli.
# Prints JSON: [{"name": "00-home", "path": "/"}, ...] to stdout.
#
# Usage: discover_wp.sh [menu-location]
#   menu-location defaults to "primary" — common theme slot names:
#   primary, main-menu, primary-menu, header-menu. List what's registered with:
#     ddev wp menu location list
#
# Requires: ddev running, wp-cli inside container, jq on host.

set -euo pipefail

LOCATION="${1:-primary}"

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required" >&2
  exit 1
fi

# Find the menu assigned to the given theme location
MENU_SLUG=$(ddev wp menu location list --format=json 2>/dev/null \
  | jq -r --arg loc "$LOCATION" '.[] | select(.location==$loc) | .menu')

if [ -z "${MENU_SLUG:-}" ] || [ "$MENU_SLUG" = "null" ]; then
  echo "ERROR: no menu assigned to location '$LOCATION'" >&2
  echo "Available locations:" >&2
  ddev wp menu location list >&2 || true
  exit 1
fi

# Export menu items and convert URLs to paths, skipping separators/customs with no URL
ddev wp menu item list "$MENU_SLUG" --format=json 2>/dev/null \
  | jq -r '
    [ .[]
      | select(.url != null and .url != "#")
      | { title: .title, url: .url }
    ]
  ' \
  | python3 -c '
import json, re, sys
from urllib.parse import urlparse

items = json.load(sys.stdin)
seen = set()
out = []
i = 0
for item in items:
  path = urlparse(item["url"]).path or "/"
  if path in seen:
    continue
  seen.add(path)
  slug = re.sub(r"[^a-z0-9]+", "-", item["title"].lower()).strip("-") or f"item-{i}"
  out.append({"name": f"{i:02d}-{slug}", "path": path})
  i += 1
json.dump(out, sys.stdout, indent=2)
sys.stdout.write("\n")
'
