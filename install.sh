#!/bin/bash
# offline install fluentd and plugins

echo "========================================================"
echo "This script requires 'sudo' privileges for some steps."
read -p "Do you want to use sudo privileges? (Y/n): " use_sudo
use_sudo=${use_sudo:-Y}

run_sudo() {
  echo "[Requested sudo command]: sudo $*"
  read -p "Do you want to execute with sudo privileges? (Y/n): " confirm
  confirm=${confirm:-Y}
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    sudo "$@"
  else
    echo "[SKIP] sudo command rejected: $*"
    return 1
  fi
}

echo "========================================================"
echo "Creating directories"
echo "========================================================"

run_sudo mkdir -p /var/log/fluent
run_sudo mkdir -p /etc/fluent

echo "========================================================"
echo "Installing Fluentd..."
echo "========================================================"

run_sudo dpkg -i fluent-package_5.0.0-1_amd64.deb
if [ $? -ne 0 ]; then
  echo "[ERROR] Fluentd installation failed."
  read -p "Do you want to try force installation? (Y/n): " ans
  ans=${ans:-Y}
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    run_sudo dpkg -i --force-all fluent-package_5.0.0-1_amd64.deb
  else
    echo "[ERROR] Force installation cancelled by user."
    exit 1
  fi
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
  echo "[WARNING] ${GEMS_DIR} directory not found. Skipping plugin installation."
  echo "[INFO] If you need plugins, ensure ${GEMS_DIR} directory exists with .gem files."
else
  # Check if fluent-gem exists
  if ! command -v /opt/fluent/bin/fluent-gem >/dev/null 2>&1; then
    echo "[ERROR] fluent-gem not found. Fluentd may not be installed correctly."
    exit 1
  fi

  # Install gems from local files
  GEM_COUNT=$(find "${GEMS_DIR}" -name "*.gem" 2>/dev/null | wc -l || echo 0)
  
  if [ "$GEM_COUNT" -eq 0 ]; then
    echo "[WARNING] No .gem files found in ${GEMS_DIR}. Skipping plugin installation."
  else
    echo "[INFO] Found ${GEM_COUNT} gem file(s) to install."
    
    # Install all .gem files
    for gemfile in "${GEMS_DIR}"/*.gem; do
      if [ -f "$gemfile" ]; then
        gemname=$(basename "$gemfile")
        echo "[INFO] Installing: ${gemname}"
        run_sudo /opt/fluent/bin/fluent-gem install --local "$gemfile" --no-document || {
          echo "[WARNING] Failed to install ${gemname} with fluent-gem, trying with system gem..."
          run_sudo gem install --local "$gemfile" --no-document || {
            echo "[WARNING] Failed to install ${gemname}. Continuing..."
          }
        }
      fi
    done
    
    echo "[INFO] Installed gem versions:"
    /opt/fluent/bin/fluent-gem list | grep -E "tiny_tds|fluent-plugin-sql|mysql2|fluent-plugin-mysql-2|activerecord-sqlserver-adapter|pg|fluent-plugin-script" || true
  fi
fi

echo "========================================================"
echo "Enabling and starting Fluentd service"
echo "========================================================"

run_sudo systemctl daemon-reload
run_sudo systemctl enable fluentd
run_sudo systemctl start fluentd

if systemctl is-active --quiet fluentd; then
  echo "[SUCCESS] Fluentd service started successfully."
else
  echo "[ERROR] Failed to start Fluentd service. Please check the logs."
  exit 1
fi

echo "========================================================"
echo "[SUCCESS] Fluentd installation completed."
echo "========================================================"
