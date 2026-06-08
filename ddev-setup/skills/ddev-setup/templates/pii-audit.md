# PII Audit — {{PROJECT}}

- **Date:** {{DATE}}
- **Database audited:** local copy imported from `{{ENVIRONMENT}}` via `ddev pull {{ENVIRONMENT}}`
- **Sanitization script:** `.ddev/scripts/sanitize-db.sh` (runs automatically on every `ddev pull` via the `post-import-db` hook in `.ddev/config.yaml`)

Every rule in the sanitize script maps to a finding below. This document records
*counts and column names only* — never actual personally identifiable
information (PII) values.

## Findings

| Table | Column(s) | Classification | Rows | Decision | Implemented rule |
|---|---|---|---|---|---|
<!-- Example row (delete): | users_field_data | mail, init, pass | confirmed PII | 1,234 | anonymize | `drush sql:sanitize` base layer | -->

Classification legend:
- **confirmed PII** — column names and sampled data both indicate PII
- **likely** — column names suggest PII; sampling inconclusive (treated as PII)
- **clean** — inspected and found to contain no PII

## Verified clean

Tables/columns that were flagged by the schema scan but inspected and cleared,
so future audits don't re-litigate them:

| Table | Column(s) | Why it's clean |
|---|---|---|
| | | |

## Verification log

| Date | Check | Result |
|---|---|---|
| {{DATE}} | Manual run of `.ddev/scripts/sanitize-db.sh` after `ddev pull {{ENVIRONMENT}}` | |
| {{DATE}} | Post-sanitize spot-check (real-looking emails outside whitelist, truncated tables empty) | |

## Re-audit triggers

Re-run the PII audit (and extend the sanitize script) when any of these happen:

- A new form, commerce, newsletter, Customer Relationship Management (CRM), or
  logging plugin/module is installed
- A new custom entity or field that stores user-submitted data is added
- A new environment with a different dataset becomes the pull source
- A compliance review asks what local copies of production data contain
