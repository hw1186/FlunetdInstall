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

# Function to download a gem and its dependencies recursively
download_gem_with_deps() {
  local gemname=$1
  local gemfile_pattern="${gemname}-*.gem"
  
  # Skip if already downloaded
  if ls "${GEMS_DIR}/${gemfile_pattern}" 2>/dev/null | head -1 >/dev/null; then
    log "  Already downloaded: ${gemname}"
    return 0
  fi
  
  log "Downloading: ${gemname}"
  
  # Fetch the gem file
  if gem fetch "${gemname}" 2>/dev/null; then
    # Move .gem file to gems directory
    if ls ${gemfile_pattern} 2>/dev/null | head -1; then
      mv ${gemfile_pattern} "${GEMS_DIR}/" 2>/dev/null || true
      log "  ✓ Downloaded: ${gemname}"
    fi
  else
    log "  ✗ Failed to fetch: ${gemname}"
    return 1
  fi
  
  # Get dependencies and download them recursively
  local deps_file=$(mktemp)
  gem dependency "${gemname}" --remote 2>/dev/null | \
    grep -E "^\s+[A-Za-z]" | \
    awk '{print $2}' | \
    sed 's/[(),]//g' | \
    awk -F' ' '{print $1}' | \
    sort -u > "$deps_file" || true
  
  if [ -s "$deps_file" ]; then
    log "  Dependencies for ${gemname}:"
    while IFS= read -r dep; do
      if [ -n "$dep" ] && [ "$dep" != "bundler" ]; then
        # Extract gem name (remove version constraints)
        local dep_name=$(echo "$dep" | sed 's/[<>=!].*//' | xargs)
        if [ -n "$dep_name" ]; then
          download_gem_with_deps "$dep_name"
        fi
      fi
    done < "$deps_file"
  fi
  rm -f "$deps_file"
}

# Download all gems and their dependencies
log "Downloading gem files and dependencies..."

for gemname in "${GEMS[@]}"; do
  download_gem_with_deps "${gemname}"
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
