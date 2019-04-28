#!/bin/bash
#変数宣言
version=3.0 #Zabbixメジャーバージョン
minorversion=latest #Zabbixマイナーバージョン or latest
amazonlinux=amzn1 #AmaznLinuxバージョン amzn1 or amzn2
proxyname= #ZabbixProxy名
agentname= #ZabbixAgent名
server= #ZabbixServerIPorFQDN
dbname=zabbix #ZabbixDB名
dbuser=zabbix #ZabbixDBユーザ名
dbpassword=zabbix #ZabbixDBパスワード
encryption= #暗号化方式 unencrypted or psk or cert
#暗号化方式pskの場合入力
pskid= #pre-shared keysアイデンティティ
#暗号化方式certの場合入力　ファイルをダウンロード可能な場所に配置してください。
cafile= #CA証明書URL
certfle= #Server証明書URL
keyfile= #秘密鍵ファイルURL

#リポジトリ登録
echo [amazon.zabbix] >> /etc/yum.repos.d/zabbix.repo
echo name=amazon.zabbix >> /etc/yum.repos.d/zabbix.repo
echo baseurl=https://s3-ap-northeast-1.amazonaws.com/amazon.zabbix/$amazonlinux/$version/\$basearch >> /etc/yum.repos.d/zabbix.repo
echo gpgcheck=0 >> /etc/yum.repos.d/zabbix.repo

#パッケージインストール
yum update
yum install --enablerepo=epel iksemel iksemel-devel -y
if [ ${minorversion} = "latest" ] && [ ${amazonlinux} = "amzn1" ] ; then
yum install zabbix-proxy-mysql zabbix-java-gateway zabbix-agent zabbix-get zabbix-sender mysql56 mysql56-server -y
elif [ ${minorversion} != "latest" ] && [ ${amazonlinux} = "amzn1" ] ; then
yum install zabbix-proxy-mysql-${minorversion} zabbix-java-gateway-${minorversion} zabbix-agent-${minorversion} zabbix-get-${minorversion} zabbix-sender-${minorversion} mysql56 mysql56-server -y
elif [ ${minorversion} = "latest" ] && [ ${amazonlinux} = "amzn2" ] ; then
amazon-linux-extras install  epel -y
yum install zabbix-server-mysql zabbix-web-mysql zabbix-web-japanese zabbix-java-gateway zabbix-agent zabbix-get zabbix-sender mariadb mariadb-server -y
else
amazon-linux-extras install epel -y
yum install zabbix-server-mysql-${minorversion} zabbix-web-mysql-${minorversion} zabbix-web-japanese-${minorversion} zabbix-java-gateway-${minorversion} zabbix-agent-${minorversion} zabbix-get-${minorversion} zabbix-sender-${minorversion} mariadb mariadb-server -y
fi

#MySql起動
if [ ${amazonlinux} = "amzn1" ] ; then
service mysqld start
else
systemctl start mariadb.service
fi

#MySql root ランダムパスワード生成
vMySQLRootPasswd="$(cat /dev/urandom | tr -dc '[:alnum:]' | head -c 16 | tee -a /home/ec2-user/.mysql.secrets)"

#MySql_secure_installation
mysql -u root --password= -e "
    UPDATE mysql.user SET Password=PASSWORD('${vMySQLRootPasswd}') WHERE User='root';
    DELETE FROM mysql.user WHERE User='';
    DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
    DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
    FLUSH PRIVILEGES;"

#ZabbixDB設定
echo [mysql] >> /home/ec2-user/my.cnf 
echo host = localhost >> /home/ec2-user/my.cnf
echo user = root >> /home/ec2-user/my.cnf
dbrootpass() {
cat /home/ec2-user/.mysql.secrets
}
dbrootpass=`dbrootpass`
echo password = ${dbrootpass} >> /home/ec2-user/my.cnf
echo "create database ${dbname} character set utf8 collate utf8_bin; grant all privileges on zabbix.* to ${dbuser}@localhost identified by '${dbpassword}';" > /tmp/create.sql
mysql --defaults-extra-file=/home/ec2-user/my.cnf < /tmp/create.sql
echo [mysql] >> /home/ec2-user/my.cnf-zabbix
echo host = localhost >> /home/ec2-user/my.cnf-zabbix
echo user = ${dbuser} >> /home/ec2-user/my.cnf-zabbix
echo password = ${dbpassword} >> /home/ec2-user/my.cnf-zabbix
echo database = ${dbname} >> /home/ec2-user/my.cnf-zabbix
docversioncheck() {
ls /usr/share/doc/ |grep zabbix-proxy |awk '{sub("^.*-","");sub("/$",""); print $0}'
}
docversion=`docversioncheck`
zcat "/usr/share/doc/zabbix-proxy-mysql-${docversion}/schema.sql.gz" | mysql --defaults-extra-file=/home/ec2-user/my.cnf-zabbix 
echo "ALTER TABLE history ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=8; ALTER TABLE history_log ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=8; ALTER TABLE history_str ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=8; ALTER TABLE history_text ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=8; ALTER TABLE history_uint ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=8; ALTER TABLE events ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=8;" > /tmp/ALTERTABLE.sql
mysql --defaults-extra-file=/home/ec2-user/my.cnf-zabbix < /tmp/ALTERTABLE.sql

#ZabbixProxy設定
sed -i -e "s/Server=127.0.0.1/Server=${server}/g" /etc/zabbix/zabbix_proxy.conf
sed -i -e "s/Hostname=Zabbix proxy/Hostname=${proxyname}/g" /etc/zabbix/zabbix_proxy.conf
sed -i -e "s/LogFileSize=0/LogFileSize=10/g" /etc/zabbix/zabbix_proxy.conf
sed -i -e "s/DBName=zabbix_proxy/DBName=${dbname}/g" /etc/zabbix/zabbix_proxy.conf
sed -i -e "s/DBUser=zabbix/DBUser=${dbuser}/g" /etc/zabbix/zabbix_proxy.conf
sed -i -e "s/# DBPassword=/DBPassword=${dbpassword}/g" /etc/zabbix/zabbix_proxy.conf
sed -i -e "s/# ProxyOfflineBuffer=1/ProxyOfflineBuffer=168/g" /etc/zabbix/zabbix_proxy.conf
sed -i -e "s/# ConfigFrequency=3600/ConfigFrequency=300/g" /etc/zabbix/zabbix_proxy.conf
sed -i -e "s/# StartPollers=5/StartPollers=10/g" /etc/zabbix/zabbix_proxy.conf
sed -i -e "s/# StartPollersUnreachable=1/StartPollersUnreachable=3/g" /etc/zabbix/zabbix_proxy.conf
sed -i -e "s/# StartPingers=1/StartPingers=5/g" /etc/zabbix/zabbix_proxy.conf
sed -i -e "s/# StartDiscoverers=1/StartDiscoverers=3/g" /etc/zabbix/zabbix_proxy.conf
sed -i -e "s/# StartHTTPPollers=1/StartHTTPPollers=3/g" /etc/zabbix/zabbix_proxy.conf
sed -i -e "s/# JavaGateway=/# JavaGateway=127.0.0.1/g" /etc/zabbix/zabbix_proxy.conf

#ZabbixAgent設定
sed -i -e "s/LogFileSize=0/LogFileSize=5/g" /etc/zabbix/zabbix_agentd.conf
sed -i -e "s# EnableRemoteCommands=0/EnableRemoteCommands=1/g" /etc/zabbix/zabbix_agentd.conf
sed -i -e "s/# LogRemoteCommands=0/LogRemoteCommands=1/g" /etc/zabbix/zabbix_agentd.conf
sed -i -e "s/Hostname=Zabbix server/Hostname=${agentname}/g" /etc/zabbix/zabbix_agentd.conf
sed -i -e "s/# RefreshActiveChecks=120/RefreshActiveChecks=60/g" /etc/zabbix/zabbix_agentd.conf
sed -i -e "s/# UnsafeUserParameters=0/UnsafeUserParameters=1/g" /etc/zabbix/zabbix_agentd.conf

#MySQLテンプレート設定
mkdir /var/lib/zabbix
cp /home/ec2-user/my.cnf /var/lib/zabbix/.my.cnf
chown zabbix.zabbix /var/lib/zabbix/.my.cnf
chmod 644 /var/lib/zabbix/.my.cnf

#psk設定
if [ ${encryption} = "psk" ] ; then
sed -i -e "s/# TLSConnect=unencrypted/TLSConnect=psk/g" /etc/zabbix/zabbix_proxy.conf
sed -i -e "s/# TLSAccept=unencrypted/TLSAccept=psk/g" /etc/zabbix/zabbix_proxy.conf
sed -i -e "s/# TLSPSKIdentity=/TLSPSKIdentity=${pskid}/g" /etc/zabbix/zabbix_proxy.conf
sed -i -e "s/# TLSPSKFile=/TLSPSKFile=\/etc\/zabbix\/tls\/.zabbix_proxy.psk/g" /etc/zabbix/zabbix_proxy.conf
mkdir /etc/zabbix/tls
openssl rand -hex 128 > /etc/zabbix/tls/.zabbix_proxy.psk
chown zabbix.zabbix /etc/zabbix/tls/.zabbix_proxy.psk
chmod 400 /etc/zabbix/tls/.zabbix_proxy.psk
fi

#cert設定
if [ ${encryption} = "cert" ] ; then
sed -i -e "s/# TLSConnect=unencrypted/TLSConnect=cert/g" /etc/zabbix/zabbix_proxy.conf
sed -i -e "s/# TLSAccept=unencrypted/TLSAccept=cert/g" /etc/zabbix/zabbix_proxy.conf
sed -i -e "s/# TLSCAFile=/TLSCAFile=\/etc\/zabbix\/tls\/zabbix_ca_file/g" /etc/zabbix/zabbix_proxy.conf
sed -i -e "s/# TLSCertFile=/TLSCertFile=\/etc\/zabbix\/tls\/zabbix.crt/g" /etc/zabbix/zabbix_proxy.conf
sed -i -e "s/# TLSAccept=unencrypted/TLSKeyFile=\/etc\/zabbix\/tls\/zabbix.key/g" /etc/zabbix/zabbix_proxy.conf
mkdir /etc/zabbix/tls
cd /etc/zabbix/tls
wget -O zabbix_ca_file ${cafile}
wget -O zabbix.crt ${certfle}
wget -O zabbix.key${keyfile}
chown zabbix.zabbix /etc/zabbix/tls/*
chmod 400 /etc/zabbix/tls/*
fi

#自動起動設定
if [ ${amazonlinux} = "amzn1" ] ; then
chkconfig zabbix-proxy on
chkconfig zabbix-agent on
chkconfig zabbix-java-gateway on
chkconfig mysqld on
else
systemctl enable zabbix-server.service
systemctl enable zabbix-agent.service
systemctl enable zabbix-java-gateway.service
systemctl enable mariadb.service
fi

reboot