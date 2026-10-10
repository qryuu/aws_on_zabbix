#!/bin/bash
# ==============================================================================
# for_8.0_update.sh
# 
# Amazon Linux 2023 上の Zabbix Server を 8.0 LTS にアップデートするスクリプト
# ==============================================================================
set -euo pipefail

timezone="Asia\/Tokyo"
targetversion="8.0"

RAW_ARCH=$(uname -m)
case "${RAW_ARCH}" in
  x86_64) ARCH="x86_64" ;;
  aarch64|arm64) ARCH="aarch64" ;;
  *) echo "Error: Unsupported architecture: ${RAW_ARCH}" >&2; exit 1 ;;
esac

# OS 検証 (Zabbix 8.0 は Amazon Linux 2023 以降が必須)
if [ -f /etc/os-release ]; then
  # shellcheck source=/dev/null
  . /etc/os-release
  if [ "${ID:-}" != "amzn" ] || [[ ! "${VERSION_ID:-}" =~ ^2023 ]]; then
    echo "Error: Zabbix 8.0 requires Amazon Linux 2023 or later." >&2
    exit 1
  fi
fi

echo "Upgrading Zabbix to ${targetversion} LTS on Amazon Linux 2023 (${ARCH})..."

# 既存サービスの停止
sudo systemctl stop zabbix-server zabbix-agent 2>/dev/null || true

# 8.0 公式リポジトリ登録 & アップデート
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

echo "Zabbix 8.0 LTS upgrade completed. System will reboot now."
sudo reboot

