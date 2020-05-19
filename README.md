# aws_on_zabbix
AWS上でのZabbix運用用スクリプト</br>
Zabbix operation script on AWS
</br>
## /UserData/Zabbix-for-RDS.sh
EC2 on MySQL で構築したZabbixServerからAMIを作成してください。
そのAMIから新たにローンチする際にこのスクリプトをUserDataに投入すると、RDSにデータを移行します。  
ZabbixServer、Zabbixフロントエンドの接続先を自動的にRDSに切り替えます。</br>
</br>
First, create AMI from Zabbix server built with EC2 of MySQL configuration.
When starting a new EC 2 instance from the created AMI, please input Zabbix for for RDS.sh into UserData.
Automatically migrate DB to RDS.
In addition, Zabbix for RDS.sh automatically switches the connection destination of Zabbix server and ZabbixWEB to RDS.
</br>
## /UserData/Launch-ZabbixProxy-on-AmazonLinux.sh
Amazon Linux にZabbixProxyを自動構築します。</br>
EC2をローンチする際にUserDataにスクリプトを投入してください。
PSK方式を使う場合は、
/etc/zabbix/tls/.zabbix_proxy.pskファイルの内容を取得して、GUIから設定を行ってください。</br>
</br>
Automatically build ZabbixProxy when launching Amazon Linux.
Please enter the script in UserData.
To use the PSK method, obtain the contents of the /etc/zabbix/tls/.zabbix_proxy.psk file and make settings from the GUI.
</br>
## /UserData/Launch-ZabbixServer-on-AmazonLinux.sh
Amazon Linux にZabbixServerを自動構築します。</br>
EC2をローンチする際にUserDataにスクリプトを投入してください。
PSK方式を使う場合は、
/etc/zabbix/tls/.zabbix_agentd.pskファイルの内容を取得して、GUIから設定を行ってください。</br>
</br>
Automatically build ZabbixServer on Amazon Linux.
Please submit script to UserData when launching EC2.
When using the PSK method,
Please obtain the contents of /etc/zabbix/tls/.zabbix_agentd.psk file and make the setting from the GUI.
</br>
## /Scripts/for_5.0_update.sh
Amazon Linux2 上に構築された任意のZabbixServerを5.0にアップデートします。
* 既存環境からAMIを作成し、UserDataにスクリプトを入力してローンチする
* 既存環境にスクリプトファイルとして配置して実行する
いずれの方法で実行することが可能です。
</br>
Update any ZabbixServer built on Amazon Linux2 to 5.0.
* Create an AMI from an existing environment and launch it by entering a script into UserData.
* Place and execute as a script file in an existing environment
It can be done either way.
</br>