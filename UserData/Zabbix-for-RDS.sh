#!/bin/bash
#変数宣言
amazonlinux=amzn2 #AmaznLinuxバージョン amzn1 or amzn2
rdsnama= #RDSエンドポイントを入力
rdsuser= #RDSMasterユーザ名
rdspassword= #RDSMasterパスワード
dbname=zabbix #移行後DB名
dbuser=zabbix #移行後DBユーザ名
dbpassword=zabbix #移行DBパスワード
#MySQL起動
if [ ${amazonlinux} = "amzn1" ] ; then
service mysqld start
else
systemctl start mariadb.service
fi
#confファイル取り込み
confdbhostget() {
cat /etc/zabbix/zabbix_server.conf |grep ^DBHost=|awk '{print substr($0,index($0,"=")+1,length($0))}'
}
confdbhost=`confdbhostget`
confdbnameget() {
cat /etc/zabbix/zabbix_server.conf |grep ^DBName=|awk '{print substr($0,index($0,"=")+1,length($0))}'
}
confdbname=`confdbnameget`
confdbuserget() {
cat /etc/zabbix/zabbix_server.conf |grep ^DBUser=|awk '{print substr($0,index($0,"=")+1,length($0))}'
}
confdbuser=`confdbuserget`
confdbpasswordget() {
cat /etc/zabbix/zabbix_server.conf |grep ^DBPassword=|awk '{print substr($0,index($0,"=")+1,length($0))}'
}
confdbpassword=`confdbpasswordget`
#dump用my.cnf
echo [mysql] >> /home/ec2-user/my.cnf 
echo host = ${confdbhost} >> /home/ec2-user/my.cnf
echo user = ${confdbuser} >> /home/ec2-user/my.cnf
echo password = ${confdbpassword} >> /home/ec2-user/my.cnf
#rdsリストア用my.cnf
echo [mysql] >> /home/ec2-user/my.cnf2
echo host = ${rdsnama} >> /home/ec2-user/my.cnf2
echo user = ${rdsuser} >> /home/ec2-user/my.cnf2
echo password = ${rdspassword} >> /home/ec2-user/my.cnf2
#config修正
sed -i -e "s/^DBHost=${confdbhost}/DBHost=${rdsnama}/g" /etc/zabbix/zabbix_server.conf
sed -i -e "s/^DBName=${confdbname}/DBName=${dbname}/g" /etc/zabbix/zabbix_server.conf
sed -i -e "s/^DBUser=${confdbuser}/DBUser=${dbuser}/g" /etc/zabbix/zabbix_server.conf
sed -i -e "s/^DBPassword=${confdbpassword}/DBPassword=${dbpassword}/g" /etc/zabbix/zabbix_server.conf
sed -i -e "s/^\$DB\['SERVER'\]   = '${confdbhost}';/\$DB\['SERVER'\]   = '${rdsnama}';/g" /etc/zabbix/web/zabbix.conf.php
sed -i -e "s/^\$DB\['DATABASE'\] = '${confdbname}';/\$DB\['DATABASE'\] = '${dbname}';/g" /etc/zabbix/web/zabbix.conf.php
sed -i -e "s/^\$DB\['USER'\]     = '${confdbuser}';/\$DB\['USER'\]     = '${dbuser}';/g" /etc/zabbix/web/zabbix.conf.php
sed -i -e "s/^\$DB\['PASSWORD'\] = '${confdbpassword}';/\$DB\['PASSWORD'\] = '${dbpassword}';/g" /etc/zabbix/web/zabbix.conf.php
#dbdump
mysqldump --defaults-extra-file=/home/ec2-user/my.cnf -N ${confdbname} > /tmp/zabbix_db.sql
#db作成
echo "create database ${dbname} character set utf8 collate utf8_bin;" > /tmp/create.sql
mysql --defaults-extra-file=/home/ec2-user/my.cnf2  < /tmp/create.sql
mysql --defaults-extra-file=/home/ec2-user/my.cnf2 -N ${dbname} < /tmp/zabbix_db.sql
#db権限変更
echo "grant all privileges on ${dbname}.* to ${dbuser}@\`%\` identified by '${dbpassword}';" > /tmp/grant.sql
mysql --defaults-extra-file=/home/ec2-user/my.cnf2 < /tmp/grant.sql
#MySQLテンプレート設定
if [ -e /var/lib/zabbix ]; then
    # 存在する場合
mv /var/lib/zabbix/.my.cnf /var/lib/zabbix/.my.cnf.org
cp /home/ec2-user/my.cnf /var/lib/zabbix/.my.cnf
chown zabbix.zabbix /var/lib/zabbix/.my.cnf
chmod 644 /var/lib/zabbix/.my.cnf
else
    # 存在しない場合
mkdir /var/lib/zabbix
cp /home/ec2-user/my.cnf /var/lib/zabbix/.my.cnf
chown zabbix.zabbix /var/lib/zabbix/.my.cnf
chmod 644 /var/lib/zabbix/.my.cnf 
fi
#作業ファイル削除
rm /tmp/zabbix_db.sql
rm /tmp/create.sql
rm /tmp/grant.sql
rm /home/ec2-user/my.cnf
rm /home/ec2-user/my.cnf2
#MySQL停止
if [ ${amazonlinux} = "amzn1" ] ; then
service mysqld stop
chkconfig mysqld off
else
systemctl stop mariadb.service
systemctl disable mariadb.service
fi