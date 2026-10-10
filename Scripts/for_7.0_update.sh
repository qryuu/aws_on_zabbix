#!/bin/bash
# ==============================================================================
# for_7.0_update.sh
# 
# Amazon Linux 2023 上の Zabbix Server を 7.0 LTS にアップデートするスクリプト
# ==============================================================================
set -euo pipefail

timezone="Asia\/Tokyo"
targetversion="7.0"

RAW_ARCH=$(uname -m)
case "${RAW_ARCH}" in
  x86_64) ARCH="x86_64" ;;
  aarch64|arm64) ARCH="aarch64" ;;
  *) echo "Unsupported architecture: ${RAW_ARCH}" >&2; exit 1 ;;
esac

echo "Upgrading Zabbix to ${targetversion} LTS on ${ARCH}..."

# 既存サービスの停止
sudo systemctl stop zabbix-server zabbix-agent 2>/dev/null || true

# リポジトリ登録 & アップデート
sudo rpm -Uvh --replacepkgs "https://repo.zabbix.com/zabbix/${targetversion}/amazonlinux/2023/${ARCH}/zabbix-release-latest-${targetversion}.amzn2023.noarch.rpm" || true
sudo dnf clean all
sudo dnf update -y

# パッケージ更新
sudo dnf install -y zabbix-server-mysql zabbix-web-mysql zabbix-apache-conf zabbix-sql-scripts zabbix-agent 2>/dev/null || \
sudo dnf install -y zabbix-server-pgsql zabbix-web-pgsql zabbix-apache-conf zabbix-sql-scripts zabbix-agent

# タイムゾーン設定
if [ -f /etc/php-fpm.d/zabbix.conf ]; then
  sudo sed -i -E "s/^[; ]*php_value\[date\.timezone\] = .*/php_value[date.timezone] = ${timezone}/" /etc/php-fpm.d/zabbix.conf
fi

sudo systemctl enable --now zabbix-server zabbix-agent httpd php-fpm || true

echo "Zabbix 7.0 LTS upgrade completed. System will reboot now."
sudo reboot

