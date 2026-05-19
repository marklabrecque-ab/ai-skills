<?php

/**
 * @file
 * Local development overrides. Loaded last by settings.php.
 *
 * This file is per-developer and gitignored. Seeded automatically by DDEV's
 * post-start hook from templates/settings.local.php in the ddev-setup skill.
 */

// Stage File Proxy: serve missing files from production instead of requiring a
// full files-directory sync. Requires the stage_file_proxy module to be
// enabled. Origin must NOT have a trailing slash.
$config['stage_file_proxy.settings']['origin'] = '{{PROD_URL}}';

// Show all errors on screen during local development.
$config['system.logging']['error_level'] = 'verbose';

// Disable CSS/JS aggregation so changes show up without a cache rebuild.
$config['system.performance']['css']['preprocess'] = FALSE;
$config['system.performance']['js']['preprocess'] = FALSE;

// Disable the render cache and dynamic page cache locally.
$settings['cache']['bins']['render'] = 'cache.backend.null';
$settings['cache']['bins']['page'] = 'cache.backend.null';
$settings['cache']['bins']['dynamic_page_cache'] = 'cache.backend.null';

// Allow test modules and themes to be installed.
$settings['extension_discovery_scan_tests'] = FALSE;

// Skip file system permission hardening warnings on local.
$settings['skip_permissions_hardening'] = TRUE;
