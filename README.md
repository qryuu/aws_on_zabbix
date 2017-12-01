# aws_on_zabbix
AWS上でのZabbix運用用スクリプト
*Zabbix-for-RDS.sh
EC2 on RDS で構築したZabbixServerのAMIを作成し、そのAMIをローンチする際にこのスクリプトをUserDataに入れると、
RDSにデータを移行します。
ZabbixServer、Zabbixフロントエンドの接続先を自動的にRDSに切り替えます。
