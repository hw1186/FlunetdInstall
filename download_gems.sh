#!/bin/bash
# ================================================================
# Fluentd Plugin & Library Downloader for Offline Installation
# Downloads gem files and dependencies for offline/air-gapped environments
# Run this script on a machine with internet access
# ================================================================

set -euo pipefail

log() { echo -e "\n>>> $*"; }

GEMS_DIR="fluentd_gems"
GEMS=(
  tiny_tds
  fluent-plugin-sql
  fluent-plugin-script
  mysql2
  fluent-plugin-mysql-2
  activerecord-sqlserver-adapter
  pg
)

# Create directory for gems
log "Creating directory for gem files: ${GEMS_DIR}"
mkdir -p "${GEMS_DIR}"

# Check if gem command exists
if ! command -v gem >/dev/null 2>&1; then
  log "[ERROR] gem command not found. Please install Ruby first."
  exit 1
fi

# Simple and fast: use gem install to download all dependencies automatically
log "Downloading gem files and dependencies..."

# Use a temporary directory to simulate installation and download all dependencies
TEMP_INSTALL_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_INSTALL_DIR}" EXIT

# Download each gem with all its dependencies
for gemname in "${GEMS[@]}"; do
  log "Downloading: ${gemname} (with dependencies)..."
  
  # Use gem install with --install-dir to download all dependencies
  # This automatically resolves and downloads all required gems
  gem install "${gemname}" \
    --install-dir "${TEMP_INSTALL_DIR}" \
    --no-document \
    --no-wrappers \
    2>&1 | grep -E "(Successfully|Installing|Fetching)" || true
  
  # Copy all downloaded .gem files to our directory
  find "${TEMP_INSTALL_DIR}/cache" -name "*.gem" 2>/dev/null | while read gemfile; do
    if [ -f "$gemfile" ]; then
      cp "$gemfile" "${GEMS_DIR}/" 2>/dev/null || true
    fi
  done
  
  # Also try direct fetch as backup
  gem fetch "${gemname}" 2>/dev/null || true
done

# Move any .gem files from current directory
find . -maxdepth 1 -name "*.gem" -exec mv {} "${GEMS_DIR}/" \; 2>/dev/null || true

# Also explicitly download known dependencies that might be missed
log "Downloading additional known dependencies..."
ADDITIONAL_DEPS=(
  jsonpath
  activerecord-import
  activerecord
  activemodel
  activesupport
  tzinfo
  concurrent-ruby
  i18n
  rack
  nokogiri
  ffi
  connection_pool
  mysql2-cs-bind
)

# Download activerecord-import version 1.x (required by fluent-plugin-sql)
log "Downloading activerecord-import version 1.x for compatibility..."
gem fetch activerecord-import -v "~> 1.0" 2>/dev/null || \
gem fetch activerecord-import -v "1.1.0" 2>/dev/null || true
if ls activerecord-import-1.*.gem 2>/dev/null | head -1; then
  mv activerecord-import-1.*.gem "${GEMS_DIR}/" 2>/dev/null || true
fi

for dep in "${ADDITIONAL_DEPS[@]}"; do
  if ! ls "${GEMS_DIR}/${dep}"-*.gem 2>/dev/null | head -1 >/dev/null; then
    log "Downloading additional dependency: ${dep}"
    gem fetch "${dep}" 2>/dev/null || true
    if ls "${dep}"-*.gem 2>/dev/null | head -1; then
      mv "${dep}"-*.gem "${GEMS_DIR}/" 2>/dev/null || true
    fi
  fi
done

# Clean up any .gem files in current directory
log "Cleaning up temporary files..."
find . -maxdepth 1 -name "*.gem" -exec mv {} "${GEMS_DIR}/" \; 2>/dev/null || true

# Remove duplicates (keep only the latest version)
log "Removing duplicate gem files (keeping latest versions)..."
cd "${GEMS_DIR}"
for gem_base in $(ls *.gem 2>/dev/null | sed 's/-[0-9].*\.gem$//' | sort -u); do
  if ls "${gem_base}"-*.gem 2>/dev/null | wc -l | grep -q "^[2-9]"; then
    # Multiple versions found, keep only the latest
    latest=$(ls -t "${gem_base}"-*.gem 2>/dev/null | head -1)
    ls "${gem_base}"-*.gem 2>/dev/null | grep -v "^${latest}$" | xargs rm -f 2>/dev/null || true
    log "  Kept latest version: $(basename "$latest")"
  fi
done
cd - >/dev/null

log "========================================================"
log "Download complete!"
log "Gem files are in: ${GEMS_DIR}/"
log "Copy this directory to your offline machine."
log "========================================================"
log "Total gem files downloaded: $(ls -1 "${GEMS_DIR}"/*.gem 2>/dev/null | wc -l || echo 0)"
