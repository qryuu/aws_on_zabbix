# aws_on_zabbix
AWS上でのZabbix運用用スクリプト
</br>
## /UserData/Zabbix-for-RDS.sh
EC2 on RDS で構築したZabbixServerのAMIを作成し、そのAMIをローンチする際にこのスクリプトをUserDataに入れると、
RDSにデータを移行します。  
ZabbixServer、Zabbixフロントエンドの接続先を自動的にRDSに切り替えます。</br>
</br>
## /UserData/Launch-ZabbixProxy-on-AmazonLinux.sh
Amazon Linux AMIにZabbixProxyを自動構築します。</br>
PSK方式を使う場合は、
/etc/zabbix/tls/.zabbix_proxy.pskファイルの内容を取得して、GUIから設定を行ってください。</br>
</br>
## /UserData/Launch-ZabbixServer-on-AmazonLinux
Amazon Linux AMIにZabbixServerを自動構築します。</br>
PSK方式を使う場合は、
/etc/zabbix/tls/.zabbix_agentd.pskファイルの内容を取得して、GUIから設定を行ってください。</br>
</br>

