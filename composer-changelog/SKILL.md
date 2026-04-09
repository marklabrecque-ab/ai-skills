---
name: composer-changelog
description: Analyzes a composer.lock diff for Drupal projects, fetches release notes and changelogs for changed production dependencies from Drupal.org, and produces a Markdown report highlighting breaking changes, deprecations, and security fixes. Always includes a summary of drupal/core changes when present. Use this skill whenever the user provides a composer.lock diff, git diff output involving composer.lock, or asks about the impact of Drupal dependency updates — even if they just say "what changed in composer", "review these package updates", "what do I need to check after this composer update", or pastes a composer.lock diff without further explanation.
---

# Composer Changelog Analyzer

You help Drupal developers understand the impact of dependency updates by analyzing a `composer.lock` diff and cross-referencing each changed package with its release notes on Drupal.org (or in-repo changelogs), then producing a concise Markdown report focused on what actually requires attention.

## Input

Start by getting the full `composer.lock` from both the old and new state — don't parse diffs. This avoids ambiguity about which JSON section a package belongs to.

**Determine the comparison base:**

1. If the user specifies a particular comparison (e.g. "between these two commits" or "on this PR"), use that.
2. Otherwise, check for unstaged changes: `git status composer.lock`
   - If modified: old = `git show HEAD:composer.lock`, new = current working copy
3. If no unstaged changes, compare to the previous commit: old = `git show HEAD~1:composer.lock`, new = `git show HEAD:composer.lock`
4. If on a feature branch, compare to the base branch: old = `git show develop:composer.lock`, new = `git show HEAD:composer.lock`

Use whichever produces a meaningful difference.

Extract the structured JSON from both versions using:

```bash
git show {ref}:composer.lock | python3 -c "
import json, sys
data = json.load(sys.stdin)
pkgs = {p['name']: p['version'] for p in data.get('packages', [])}
json.dump(pkgs, sys.stdout)
"
```

Do the same for the new version, then diff the two dictionaries to get a clean list of changed production packages. This eliminates any ambiguity about `packages` vs. `packages-dev`.

You may also reference `composer.json` if available.

## Step 0: Run `composer audit`

Before any changelog analysis, run:

```bash
composer audit --format=json
```

This queries the Packagist/FriendsOfPHP security advisories database and gives immediate results for known vulnerabilities. Record any advisories found — these will be included in the report's Security section and complement the Drupal.org SA lookup in Step 2.

If `composer audit` is not available (older Composer versions), skip this step silently.

## Step 1: Extract changed production packages

Using the structured comparison from the Input step, for each package present in the `"packages"` array, record:
- Package name (e.g. `drupal/paragraphs`)
- Old version → new version

**Skip known metapackages that have no release notes:**
- `drupal/core-recommended`
- `drupal/core-composer-scaffold`
- `drupal/core-project-message`
- `drupal/core-dev`
- `drupal/core-dev-pinned`

These are wrappers around `drupal/core` — only `drupal/core` itself has release notes.

## Step 1b: Check patches on changed packages

Read `composer.json` and look for a `patches` key under `extra` — this is the standard `cweagans/composer-patches` format:

```json
{
  "extra": {
    "patches": {
      "drupal/paragraphs": {
        "Fix for issue #123": "patches/paragraphs-fix.patch",
        "Upstream patch": "https://www.drupal.org/files/issues/2024-01-01/patch.patch"
      }
    }
  }
}
```

For each production package that was **updated**, check whether it has any entries in `extra.patches`.

If it does, for each patch:

### a) Check if the patch still applies cleanly

Run a dry-run patch against the installed package in `vendor/`:

```bash
patch --dry-run -p1 -d vendor/{package-path} < {patch-file}
```

For local patch files, use the path directly. For URL patches, fetch the patch to a temp file first, then test it.

If `patch --dry-run` exits non-zero, the patch **no longer applies cleanly** — flag it.

### b) If the patch doesn't apply — check if it's still needed

When a patch fails to apply, determine whether the underlying issue has been fixed upstream in the new version:

1. **Inspect what the patch changes**: Read the patch file/content and identify the specific lines it modifies.
2. **Check the current installed files**: Look at the relevant file(s) in `vendor/{package-path}/` and determine if:
   - The "before" state (lines the patch removes) no longer exists — suggests the code was refactored or replaced
   - The "after" state (lines the patch adds) already exists — confirms the fix was merged upstream
3. **Cross-reference with release notes**: Check the changelog fetched in Step 2 for any mention of the issue number or the specific bug the patch addresses. Drupal.org patch URLs often contain the issue node ID (e.g. `/files/issues/2024-01-01/1234567-fix.patch`) — search the release notes for that issue number.

Conclude one of:
- **Patch no longer needed**: The fix is present in the new version — the patch entry should be removed from `composer.json`
- **Patch still needed but doesn't apply**: The issue isn't fixed upstream and the patch needs to be rebased/updated against the new version
- **Unclear**: The code structure changed significantly and manual review is needed

## Step 2: Fetch changelogs

For each changed production package:

### Drupal.org packages (`drupal/*`)

The project machine name is the part after `drupal/` in the package name — with one exception: `drupal/core` maps to project name `drupal`.

#### Step 2a: Fetch the XML release history feed

For each Drupal project, fetch the update status XML feed (one request per project):

```
https://updates.drupal.org/release-history/{project_name}/current
```

Examples:
- `drupal/core` → `https://updates.drupal.org/release-history/drupal/current`
- `drupal/paragraphs` → `https://updates.drupal.org/release-history/paragraphs/current`

This returns structured XML with all releases. Each `<release>` element includes:
- `<version>` — the canonical version string as Drupal.org knows it
- `<tag>` — the git tag
- `<terms>` — release type taxonomy: "Security update", "Bug fixes", "New features"
- `<release_link>` — URL to the release page
- `<date>` — release timestamp

**Use this feed to:**
1. **Resolve version format mismatches.** Composer may report `1.18.0` while Drupal.org uses `8.x-1.18` (legacy format) or vice versa. Match by checking both formats against the feed's `<version>` values. Try the composer version first; if no match, try `8.x-{major}.{minor}` format (dropping trailing `.0` patch). The XML feed is the authoritative source for the correct version string.
2. **Enumerate intermediate versions.** If multiple versions were skipped (e.g. 1.15 → 1.18), use the feed to list all versions between old and new.
3. **Classify releases by type.** Use the `<terms>` data to identify security updates, new features, and bug-fix-only releases without needing to read the full release notes.

#### Step 2b: Triage which releases need full notes

Using the XML feed's structured release type terms:
- **Security updates and new feature releases**: fetch full release note bodies (Step 2c)
- **Bug-fix-only releases**: use `field_release_short_description` from the JSON API (see below) for a one-liner summary — no need to fetch the full body unless the package is `drupal/core`

#### Step 2c: Fetch release note bodies via the JSON API

For releases that need full notes, use the Drupal.org JSON API instead of scraping HTML:

```
https://www.drupal.org/api-d7/node.json?type=project_release&title={project_name}+{version}
```

**Important:** The `field_project_machine_name` filter does NOT work for `project_release` nodes. Filter by `title` instead — release node titles follow the format `{project_name} {version}`.

Examples:
- `https://www.drupal.org/api-d7/node.json?type=project_release&title=paragraphs+8.x-1.18`
- `https://www.drupal.org/api-d7/node.json?type=project_release&title=drupal+10.3.6`
- `https://www.drupal.org/api-d7/node.json?type=project_release&title=gin+3.0.0-rc10`

Each result includes:
- `body.value` — full HTML release notes
- `field_release_short_description` — curated one-liner from the maintainer (use this for the "No Action Required" summary)

Use the canonical version string from the XML feed (Step 2a) in the title query to ensure a match.

#### Step 2d: Check for security advisories

For each changed Drupal project, query the security advisory API:

```
https://www.drupal.org/api-d7/node.json?type=sa&field_project={project_nid}
```

The project node ID (`project_nid`) can be extracted from the XML feed's `<release_link>` URLs or by querying:
```
https://www.drupal.org/api-d7/node.json?type=project_module&field_project_machine_name={project_name}
```

Each SA includes:
- `field_sa_advisory_id` — e.g. SA-CONTRIB-2024-001
- `field_sa_criticality` — severity level
- `field_sa_cve` — CVE identifiers
- `field_affected_versions` — which versions are affected
- `field_fixed_in` — which versions contain the fix

Check if any SA's affected versions overlap with the old version and `field_fixed_in` includes the new version. This gives definitive "this update fixes SA-CONTRIB-2024-XXX" information.

If the API returns errors or rate-limits, fall back to checking the `<terms>` data from the XML feed for "Security update" flags.

### In-repo CHANGELOG.md

Some packages include a `CHANGELOG.md` in their repository. If the package metadata in `composer.lock` includes a source URL pointing to GitHub or GitLab, you can try to fetch the raw changelog file. Prefer Drupal.org release notes when both are available.

### Non-Drupal packages

For non-`drupal/*` packages (e.g. Symfony components, Guzzle, third-party libraries), fetch their GitHub releases page or CHANGELOG.md. These are lower priority — only include them if you find explicit breaking changes or security advisories. Also check if `composer audit` (Step 0) flagged any advisories for these packages.

## Step 3: Determine what's high-impact

Use the structured data from Step 2 to classify each package:

**Primary signals (from XML feed `<terms>` and SA API):**
- **Security fixes** — releases tagged "Security update" in the XML feed, or matched by the SA API (Step 2d), or flagged by `composer audit` (Step 0)
- **Breaking changes / new features** — releases tagged "New features" in the XML feed, then confirmed by reading the full release notes body

**Secondary signals (from release note bodies, only fetched for non-bug-fix releases):**
- **Deprecations** — hooks, APIs, or patterns marked for removal in a future version
- **Required manual steps** — database updates needed, config changes, hook renames
- **Behavior changes** — API changes, config structure changes, removed features

**Skip a package entirely** from the main report if:
- All intermediate releases are tagged "Bug fixes" only in the XML feed and `field_release_short_description` confirms no behavioral impact
- There are no release notes at all
- It's a patch-level bump with nothing noteworthy

**Exception: always include `drupal/core`** — summarize its changes regardless of bump size or content.

## Step 4: Scan for affected custom code

For any package with breaking changes or deprecations, search the project's custom code for usage of the changed APIs, hooks, or functions. Custom code lives in:
- `web/modules/custom/`
- `web/themes/custom/`
- `web/profiles/custom/` (if present)

What to search for depends on what changed. Use the specific symbols from the release notes:
- **Renamed/removed hooks**: grep for the old hook name (e.g. `hook_node_presave` → search for `_node_presave`)
- **Deprecated/removed functions or classes**: grep for the function/class name
- **Changed service names or plugin IDs**: grep for the old ID string
- **Config schema changes**: check for `.yml` files in custom module config directories that use the old structure

For each match found, record the file path, line number, and a snippet of context. Be specific — "File X uses deprecated function Y on line Z" is far more useful than "custom code may be affected."

If no custom code is found using the changed API, say so explicitly rather than omitting this section — it's reassuring to confirm the coast is clear.

## Step 5: Write the Markdown report

Save to `docs/composer-update-notes.md` unless the user specifies another path.

Use this structure:

```markdown
# Composer Update Notes
Generated: {YYYY-MM-DD}

## Summary
{1–2 sentences: how many packages changed, any immediate risks or things to flag. Always call out patches that no longer apply or need rebasing — these are blocking issues for deployment.}

---

## Security Advisories

{Include this section if `composer audit` or the Drupal.org SA API (Step 2d) found any advisories.}

### {advisory_id} — {package_name}
**Severity:** {criticality level}
**CVE:** {CVE ID, if available}
**Affected versions:** {affected range}
**Fixed in:** {new_version}

{Brief description of the vulnerability and its impact.}

---

## drupal/core
**{old_version} → {new_version}**

{Summary of what changed — security fixes, new APIs, deprecations, behavioral changes.}

[Release notes]({url})

---

## Patch Status

### drupal/{package}
**{patch description}** (`{patch file or URL}`)

{One of the following:}

- **Still applies cleanly** — no action needed
- **No longer applies — patch is no longer needed**: The fix from this patch is present in {new_version}. Remove this entry from `composer.json`'s `extra.patches`.
- **No longer applies — patch still needed**: The upstream issue is not fixed in {new_version}. The patch must be rebased against the new version before this update can be deployed.
- **No longer applies — unclear**: The code structure changed significantly. Manual review required to determine if the patch is still relevant.

---

## High-Impact Changes

### drupal/{package}
**{old_version} → {new_version}**

#### What changed
{Detailed description of the breaking change or deprecation. Include:
- The specific function/hook/API/config that changed
- What it changed to (new name, new signature, replacement, etc.)
- Any migration path or upgrade guide mentioned in the release notes
- Whether a database update is required}

#### Custom code impact
{One of:
- List of affected files with file path, line number, and relevant snippet
- "No custom code found using this API — no action needed"}

**Action required:** {Concrete next steps — specific enough to act on without re-reading the release notes}

[Release notes]({url})

---

## Packages Updated — No Action Required
- `drupal/foo`: 1.4.0 → 1.5.0 — {use field_release_short_description if available, otherwise "bug fixes only"}
- `drupal/bar`: 2.1.1 → 2.1.3 — (changelog unavailable)
```

**Formatting notes:**
- For breaking changes, be thorough — a developer should be able to act on this report without needing to read the full release notes themselves
- For the "No Action Required" list, keep it brief — one line per package. Use `field_release_short_description` from the JSON API when available for a curated summary; fall back to "bug fixes only" or "(changelog unavailable)"
- If the "No Action Required" list exceeds ~10 items, replace it with a count in the Summary instead
- If "Action required" is genuinely none, omit that line rather than writing "None"
- Omit the **Security Advisories** section if `composer audit` and the SA API found no advisories
- Omit the **Patch Status** section entirely if no updated packages have patches configured — don't include it as an empty section
- If all patches on updated packages still apply cleanly, note this briefly in the Summary and omit the Patch Status section
- In the Summary, always call out patches that no longer apply or need rebasing — these are blocking issues for deployment

## If something goes wrong

- If Drupal.org returns an error or rate-limits, retry with exponential backoff (wait 1s, then 3s) before marking as unavailable. Prefer the XML feed (one request per project) over individual page fetches to minimize total request count.
- If the JSON API title query returns no results, try alternate version formats: if you queried with semver `1.18.0`, retry with `8.x-1.18`; if you queried with `8.x-` prefix, retry with plain semver. The XML feed's `<version>` values are authoritative.
- If `composer audit` fails or is unavailable, continue without it — the Drupal.org SA API lookup in Step 2d provides similar coverage for Drupal packages.
- If the SA API query requires a project node ID you can't resolve, fall back to checking the XML feed's `<terms>` for "Security update" flags — this still identifies security releases, just without the detailed advisory metadata.
