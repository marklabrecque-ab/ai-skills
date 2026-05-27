<?php
/**
 * Local wp-config bootstrap. Committed to version control.
 *
 * The ddev-setup skill wires a pre-start hook that copies this file to
 * wp-config.php on first `ddev start` if wp-config.php is missing.
 * wp-config.php itself is gitignored (it's the local/generated file).
 *
 * DDEV auto-generates wp-config-ddev.php with DB credentials and URLs on
 * start; it's included below. Per-project overrides (e.g. $table_prefix)
 * belong in wp-config-override.php, which is included LAST so it wins.
 */

// Mark this environment as local. WordPress core's wp_get_environment_type()
// defaults to 'production' when this constant is unset, so prod (which never
// receives this file — wp-config.php is gitignored) stays fail-closed.
if (!defined("WP_ENVIRONMENT_TYPE")) define("WP_ENVIRONMENT_TYPE", "local");

// DDEV-managed database credentials, URLs, etc.
if (file_exists(__DIR__ . "/wp-config-ddev.php")) {
    require_once __DIR__ . "/wp-config-ddev.php";
}

$table_prefix = "wp_";

// stage_file_proxy: fetch missing uploads from production on demand.
// Gated on WP_ENVIRONMENT_TYPE so that even if this define somehow leaked
// into a committed file, prod (where WP_ENVIRONMENT_TYPE is undefined or
// 'production') bails. We check the constant directly rather than calling
// wp_get_environment_type() because WordPress core isn't loaded yet at
// wp-config parse time.
//
// NOTE: the current upstream alleyinteractive/stage-file-proxy (Version: 100)
// does NOT read this constant — it reads wp_options.sfp_url via get_option().
// This define is decorative for that plugin (kept as defense-in-depth for
// forks that respect the constant, e.g. Automattic VIP's, and as a runtime
// signal for project code that wants to branch on "is this a local proxy
// environment?"). The runtime configuration that actually enables fetching
// lives in the sfp_url DB option, set via a post-import-db hook in
// .ddev/config.yaml. See SKILL.md Step 5b.3 / 5b.4.
if (defined("WP_ENVIRONMENT_TYPE") && WP_ENVIRONMENT_TYPE !== "production") {
    if (!defined("STAGE_FILE_PROXY_URL")) define("STAGE_FILE_PROXY_URL", "{{STAGE_FILE_PROXY_URL}}");
}

// DDEV's wp-config-ddev.php already defines WP_DEBUG. Guard to avoid a
// duplicate-define warning that prints before <!DOCTYPE> and breaks layout.
if (!defined("WP_DEBUG")) define("WP_DEBUG", true);
if (!defined("WP_DEBUG_LOG")) define("WP_DEBUG_LOG", true);
if (!defined("WP_DEBUG_DISPLAY")) define("WP_DEBUG_DISPLAY", false);

// Salts — fetched fresh from https://api.wordpress.org/secret-key/1.1/salt/
// at file generation time by the ddev-setup skill.
{{SALTS}}

if (!defined("ABSPATH")) {
    define("ABSPATH", __DIR__ . "/");
}

// Per-project overrides — loaded last so they win over everything above.
if (file_exists(__DIR__ . "/wp-config-override.php")) {
    require_once __DIR__ . "/wp-config-override.php";
}

require_once ABSPATH . "wp-settings.php";
