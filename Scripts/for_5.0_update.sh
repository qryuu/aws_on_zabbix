#!/bin/bash
# ==============================================================================
# for_5.0_update.sh
# 
# Amazon Linux 2 上に構築された Zabbix 4.0 環境を 5.0 LTS にアップデートするスクリプト
# ==============================================================================
set -euo pipefail

timezone="Asia\/Tokyo"
baseversion="4.0"
targetversion="5.0"

echo "Upgrading Zabbix from ${baseversion} to ${targetversion}..."

# リポジトリ設定の書き換え (公式またはローカルリポジトリ)
if [ -f /etc/yum.repos.d/zabbix.repo ]; then
  sudo sed -i -E "s/([/])${baseversion}([/])/\1${targetversion}\2/g" /etc/yum.repos.d/zabbix.repo
fi

# 競合ブロッカーのアンインストール
sudo yum remove -y phpMyAdmin php-tidy 2>/dev/null || true

# 依存パッケージ更新 (Amazon Linux 2 extras)
sudo amazon-linux-extras install -y lamp-mariadb10.2-php7.2 php7.2 || true

# パッケージアップデート実行
sudo yum update -y

# 追加パッケージインストール
sudo yum install -y zabbix-apache-conf zabbix-js || true

# タイムゾーン設定
if [ -f /etc/php-fpm.d/zabbix.conf ]; then
  sudo sed -i -E "s/^[; ]*php_value\[date\.timezone\] = .*/php_value[date.timezone] = ${timezone}/" /etc/php-fpm.d/zabbix.conf
fi

# php-fpm 有効化
sudo systemctl enable php-fpm.service

echo "Zabbix 5.0 upgrade completed. System will reboot now."
sudo reboot