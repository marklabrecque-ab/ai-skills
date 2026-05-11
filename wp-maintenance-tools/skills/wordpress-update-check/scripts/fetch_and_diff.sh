#!/usr/bin/env bash
# Fetch a plugin's old and new version from wp.org (or use installed dir as old),
# then write a unified diff, a changed-files list, and an extracted changelog.
#
# Usage:
#   fetch_and_diff.sh <slug> <current-version> <new-version> <run-dir> [flags]
#
# Flags (any order, after the four positional args):
#   --use-installed-as-old     Skip downloading the old version; copy the
#                              site's installed plugin dir instead.
#   --new-url <url>            Download the new version from this URL instead
#                              of the default wp.org location. Useful for
#                              premium plugins where the vendor's signed URL
#                              (from `wp plugin list --field=update_package`)
#                              is still valid.
#
# Outputs into <run-dir>/<slug>/:
#   old/                   (extracted old plugin tree)
#   new/                   (extracted new plugin tree)
#   diff.patch             (diff -urN old new)
#   changed-files.txt      (A/M/D path)
#   changelog.txt          (extracted from new/readme.txt if present)
#
# Exit codes:
#   0 success
#   2 download failed (treat as "skip")
#   3 bad arguments

set -euo pipefail

if [ "$#" -lt 4 ]; then
  echo "Usage: $0 <slug> <current-version> <new-version> <run-dir> [--use-installed-as-old] [--new-url <url>]" >&2
  exit 3
fi

SLUG="$1"
OLD_VER="$2"
NEW_VER="$3"
# Absolute path so the inner `cd` calls don't break relative targets.
RUN_DIR="$(cd "$4" && pwd)"
shift 4

USE_INSTALLED_OLD="false"
NEW_URL=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --use-installed-as-old)
      USE_INSTALLED_OLD="true"
      shift
      ;;
    --new-url)
      if [ "$#" -lt 2 ]; then
        echo "ERROR: --new-url requires a URL argument" >&2
        exit 3
      fi
      NEW_URL="$2"
      shift 2
      ;;
    *)
      echo "ERROR: unknown flag: $1" >&2
      exit 3
      ;;
  esac
done

WORK="$RUN_DIR/$SLUG"
mkdir -p "$WORK/old" "$WORK/new"

WP_DOWNLOAD="https://downloads.wordpress.org/plugin"

fetch_zip() {
  # fetch_zip <url> <out-zip>
  local url="$1"
  local out="$2"
  curl -fsSL --max-time 60 -o "$out" "$url"
}

extract_zip() {
  # extract_zip <zip> <target-dir>
  local zip="$1"
  local target="$2"
  local tmp
  tmp="$(mktemp -d)"
  unzip -q "$zip" -d "$tmp"
  # wp.org zips wrap content in a top-level <slug>/ directory; flatten it.
  local inner
  inner="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  if [ -n "$inner" ]; then
    # Move inner contents up
    (cd "$inner" && find . -mindepth 1 -maxdepth 1 -exec mv {} "$target"/ \;)
  else
    (cd "$tmp" && find . -mindepth 1 -maxdepth 1 -exec mv {} "$target"/ \;)
  fi
  rm -rf "$tmp"
}

# --- new version: required ---
NEW_ZIP="$WORK/new.zip"
NEW_ZIP_URL="${NEW_URL:-$WP_DOWNLOAD/${SLUG}.${NEW_VER}.zip}"
if ! fetch_zip "$NEW_ZIP_URL" "$NEW_ZIP"; then
  echo "ERROR: failed to download new version ${SLUG} ${NEW_VER} from $NEW_ZIP_URL" >&2
  exit 2
fi
extract_zip "$NEW_ZIP" "$WORK/new"

# --- old version: from wp.org or installed ---
if [ "$USE_INSTALLED_OLD" = "true" ]; then
  # Locate installed plugin dir. Try common WP layouts.
  INSTALLED=""
  for candidate in \
    "wp-content/plugins/$SLUG" \
    "web/wp-content/plugins/$SLUG" \
    "public_html/wp-content/plugins/$SLUG"
  do
    if [ -d "$candidate" ]; then
      INSTALLED="$candidate"
      break
    fi
  done
  if [ -z "$INSTALLED" ]; then
    echo "ERROR: --use-installed-as-old set but could not locate wp-content/plugins/$SLUG" >&2
    exit 2
  fi
  # Copy so diff paths look symmetric. INSTALLED may be relative to CWD.
  INSTALLED_ABS="$(cd "$INSTALLED" && pwd)"
  (cd "$INSTALLED_ABS" && find . -mindepth 1 -maxdepth 1 -exec cp -R {} "$WORK/old"/ \;)
else
  OLD_ZIP="$WORK/old.zip"
  if ! fetch_zip "$WP_DOWNLOAD/${SLUG}.${OLD_VER}.zip" "$OLD_ZIP"; then
    echo "ERROR: failed to download old version ${SLUG} ${OLD_VER} from wp.org" >&2
    exit 2
  fi
  extract_zip "$OLD_ZIP" "$WORK/old"
fi

# --- diff ---
# diff returns 1 when files differ; don't let `set -e` kill us.
diff -urN "$WORK/old" "$WORK/new" > "$WORK/diff.patch" || true

# --- changed-files.txt ---
{
  # Added in new
  (cd "$WORK/new" && find . -type f) | sort > "$WORK/.new-files"
  (cd "$WORK/old" && find . -type f) | sort > "$WORK/.old-files"
  comm -23 "$WORK/.new-files" "$WORK/.old-files" | sed 's/^/A /'
  comm -13 "$WORK/.new-files" "$WORK/.old-files" | sed 's/^/D /'
  # Modified: in both, content differs
  comm -12 "$WORK/.new-files" "$WORK/.old-files" | while IFS= read -r f; do
    if ! cmp -s "$WORK/old/$f" "$WORK/new/$f"; then
      echo "M $f"
    fi
  done
} > "$WORK/changed-files.txt"
rm -f "$WORK/.new-files" "$WORK/.old-files"

# --- changelog.txt ---
README="$WORK/new/readme.txt"
if [ -f "$README" ]; then
  # Extract from "== Changelog ==" to next top-level section or EOF.
  awk '
    /^==[[:space:]]*Changelog[[:space:]]*==/ { found=1; print; next }
    found && /^==[[:space:]]*[^=]+[[:space:]]*==/ { exit }
    found { print }
  ' "$README" > "$WORK/changelog.txt"
fi

echo "OK: $SLUG ${OLD_VER} -> ${NEW_VER}"
echo "  diff:           $WORK/diff.patch ($(wc -l < "$WORK/diff.patch") lines)"
echo "  changed files:  $WORK/changed-files.txt ($(wc -l < "$WORK/changed-files.txt") entries)"
if [ -f "$WORK/changelog.txt" ]; then
  echo "  changelog:      $WORK/changelog.txt"
fi
