# aws_on_zabbix
AWS上でのZabbix運用用スクリプト</br>
Zabbix operation script on AWS
</br>
## /UserData/Zabbix-for-RDS.sh
EC2 on MySQL で構築したZabbixServerからAMIを作成してください。
そのAMIから新たにローンチする際にこのスクリプトをUserDataに投入すると、RDSにデータを移行します。  
ZabbixServer、Zabbixフロントエンドの接続先を自動的にRDSに切り替えます。</br>
</br>
" EC 2 on MySQL" kōsei de kōchiku shita ZabbixServer no ami o sakusei shimasu. Sono ami o riyō shite arata ni EC 2 o rōnchi suru toki ni sukuriputo o UserData ni tōnyū suru koto ni yotte, dēta o RDS ni ikō shimasu. ZabbixServer, Zabbix furontoendo no setsuzoku-saki DB o jidōtekini ikō shita RDS ni kirikaemasu.
Create AMI of ZabbixServer built with "EC 2 on MySQL" configuration.
When launching a new EC 2 using that AMI, we will transfer the data to RDS by inserting a script into UserData.
ZabbixServer, Zabbix Switch the connection destination DB of the front end to RDS automatically migrated.
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
