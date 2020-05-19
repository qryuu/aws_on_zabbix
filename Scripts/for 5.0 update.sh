#!/bin/bash
#変数宣言
timezone="Asia\/Tokyo"
baseversion=4.0

#repodata書換
sudo sed -i -e "s/${baseversion}/5.0/g" /etc/yum.repos.d/zabbix.repo

#Blockerアンインストール
sudo yum remove -y phpMyAdmin php-tidy

#依存パッケージ更新
sudo amazon-linux-extras install -y lamp-mariadb10.2-php7.2 php7.2

#アップデート実行
sudo yum update -y

#追加パッケージインストール
sudo yum install -y zabbix-apache-conf zabbix-js 

#タイムゾーン設定
sudo sed -i -e "s/; php_value\[date.timezone\] = Europe\/Riga/php_value\[date.timezone\] = ${timezone}/g" /etc/php-fpm.d/zabbix.conf

#追加パッケージ起動設定
sudo systemctl enable php-fpm.service

#再起動
sudo reboot