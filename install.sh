#!/bin/bash
# offline install fluentd and plugins

set -uo pipefail

echo "========================================================"
echo "Creating directories"
echo "========================================================"

sudo mkdir -p /var/log/fluent
sudo mkdir -p /etc/fluent

echo "========================================================"
echo "Installing Fluentd..."
echo "========================================================"

sudo dpkg -i fluent-package_5.0.0-1_amd64.deb
if [ $? -ne 0 ]; then
  echo "[ERROR] Fluentd installation failed." >&2
  sudo dpkg -i --force-all fluent-package_5.0.0-1_amd64.deb || {
    echo "[ERROR] Force installation failed." >&2
    exit 1
  }
fi
rm fluent-package_5.0.0-1_amd64.deb

echo "========================================================"
echo "Installing Fluentd plugins from local gem files..."
echo "========================================================"
echo "[NOTE] System dependencies (freetds-dev, build-essential, libmysqlclient-dev, libpq-dev)"
echo "       must be pre-installed on the system for gem compilation."
echo "========================================================"

GEMS_DIR="fluentd_gems"

if [ ! -d "${GEMS_DIR}" ]; then
  echo "[ERROR] ${GEMS_DIR} directory not found." >&2
  exit 1
fi

if ! command -v /opt/fluent/bin/fluent-gem >/dev/null 2>&1; then
  echo "[ERROR] fluent-gem not found." >&2
  exit 1
fi

GEM_COUNT=$(find "${GEMS_DIR}" -name "*.gem" 2>/dev/null | wc -l || echo 0)

if [ "$GEM_COUNT" -eq 0 ]; then
  echo "[ERROR] No .gem files found in ${GEMS_DIR}." >&2
  exit 1
fi

cd "${GEMS_DIR}"

# Install dependencies first
for dep_gem in connection_pool mysql2-cs-bind; do
  if ls "${dep_gem}"-*.gem 2>/dev/null | head -1 >/dev/null; then
    sudo /opt/fluent/bin/fluent-gem install --local "${dep_gem}"-*.gem --no-document >/dev/null 2>&1 || true
  fi
done

# Install activerecord-import version 1.x if available
if ls activerecord-import-1.*.gem 2>/dev/null | head -1 >/dev/null; then
  sudo /opt/fluent/bin/fluent-gem install --local activerecord-import-1.*.gem --no-document >/dev/null 2>&1 || true
fi

# Try batch installation
INSTALL_OUTPUT=$(sudo /opt/fluent/bin/fluent-gem install --local *.gem --no-document 2>&1)
INSTALL_EXIT_CODE=$?

if [ "$INSTALL_EXIT_CODE" -ne 0 ]; then
  # If batch fails, try individual installation
  for gemfile in *.gem; do
    if [ -f "$gemfile" ]; then
      gemname=$(basename "$gemfile" .gem | sed 's/-[0-9].*//')
      if /opt/fluent/bin/fluent-gem list | grep -q "^${gemname} "; then
        continue
      fi
      sudo /opt/fluent/bin/fluent-gem install --local "$gemfile" --no-document >/dev/null 2>&1 || true
    fi
  done
fi

cd - >/dev/null

sudo systemctl daemon-reload >/dev/null 2>&1 || { echo "[ERROR] Failed to reload systemd daemon."; exit 1; }
sudo systemctl enable fluentd >/dev/null 2>&1 || { echo "[ERROR] Failed to enable fluentd service."; exit 1; }
sudo systemctl start fluentd >/dev/null 2>&1 || { echo "[ERROR] Failed to start fluentd service."; exit 1; }

# Check installed plugins
INSTALLED_PLUGINS=$(/opt/fluent/bin/fluent-gem list | grep -E "(fluent-plugin-sql|fluent-plugin-mysql-2|fluent-plugin-script|tiny_tds|mysql2|pg|activerecord-sqlserver-adapter|jsonpath|connection_pool)" | wc -l || echo 0)

if systemctl is-active --quiet fluentd 2>/dev/null; then
  if [ "$INSTALLED_PLUGINS" -gt 0 ]; then
    echo "[SUCCESS] Fluentd plugins installed successfully."
  else
    echo "[ERROR] Fluentd service started but no plugins were installed." >&2
    exit 1
  fi
else
  echo "[ERROR] Failed to start Fluentd service." >&2
  exit 1
fi
