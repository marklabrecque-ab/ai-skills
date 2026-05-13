#!/usr/bin/env bash
# Ensures the dependencies the youtube-playlist-url MCP needs are installed:
#   - Homebrew (only prompted; the official installer requires interaction)
#   - yt-dlp (installed via brew if missing and the user agrees)
#   - node_modules under this directory (npm install)
#
# Safe to re-run. Exits 0 when everything is in place, non-zero otherwise.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

say() { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

confirm() {
  local prompt="$1"
  local reply
  read -r -p "$prompt [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

# --- Homebrew ---
if ! command -v brew >/dev/null 2>&1; then
  warn "Homebrew is not installed."
  cat >&2 <<'EOF'

Install it with:
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

This is an interactive installer (sudo, license prompt) so it is not run
automatically. Re-run this setup script after Homebrew is installed.
EOF
  exit 1
fi
say "Homebrew detected: $(brew --version | head -1)"

# --- yt-dlp ---
if ! command -v yt-dlp >/dev/null 2>&1; then
  warn "yt-dlp not found."
  if confirm "Install yt-dlp via 'brew install yt-dlp'?"; then
    brew install yt-dlp
  else
    fail "yt-dlp is required. Install with: brew install yt-dlp"
  fi
else
  say "yt-dlp detected: $(yt-dlp --version)"
fi

# --- node_modules ---
if [[ ! -d "$HERE/node_modules" ]]; then
  say "Installing MCP server dependencies..."
  (cd "$HERE" && npm install --silent)
else
  say "node_modules already present."
fi

say "Setup complete. Restart Claude Code to load the MCP."
