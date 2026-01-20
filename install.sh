#!/bin/bash
# setup_ubuntu.sh
# Before running: chmod +x setup_ubuntu.sh

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
echo "Extracting Fluentd installation files..."
echo "========================================================"

unzip fluentd_install_scripts_ubuntu.zip
if [ $? -ne 0 ]; then
  echo "[ERROR] Extraction failed. Exiting."
  exit 1
fi
rm fluentd_install_scripts_ubuntu.zip

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
echo "Enabling and starting Fluentd service"
echo "========================================================"

run_sudo /opt/fluent/bin/fluent-gem install fluent-plugin-script
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
