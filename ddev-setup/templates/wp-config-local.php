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

// DDEV-managed database credentials, URLs, etc.
if (file_exists(__DIR__ . '/wp-config-ddev.php')) {
  require_once __DIR__ . '/wp-config-ddev.php';
}

$table_prefix = 'wp_';

define('WP_DEBUG', true);
define('WP_DEBUG_LOG', true);
define('WP_DEBUG_DISPLAY', false);

// Replace with real values from https://api.wordpress.org/secret-key/1.1/salt/
define('AUTH_KEY',         'put your unique phrase here');
define('SECURE_AUTH_KEY',  'put your unique phrase here');
define('LOGGED_IN_KEY',    'put your unique phrase here');
define('NONCE_KEY',        'put your unique phrase here');
define('AUTH_SALT',        'put your unique phrase here');
define('SECURE_AUTH_SALT', 'put your unique phrase here');
define('LOGGED_IN_SALT',   'put your unique phrase here');
define('NONCE_SALT',       'put your unique phrase here');

if (!defined('ABSPATH')) {
  define('ABSPATH', __DIR__ . '/');
}

// Per-project overrides — loaded last so they win over everything above.
if (file_exists(__DIR__ . '/wp-config-override.php')) {
  require_once __DIR__ . '/wp-config-override.php';
}

require_once ABSPATH . 'wp-settings.php';
