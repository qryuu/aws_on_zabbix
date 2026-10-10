#!/bin/bash
# ==============================================================================
# Launch-ZabbixServer-on-AmazonLinux.sh
# 
# Amazon Linux 2023 / Amazon Linux 2 上に Zabbix Server (8.0 LTS / 7.0 LTS / 6.0 LTS)
# を自動構築する EC2 UserData スクリプト
# (CPU アーキテクチャおよび Amazon Linux バージョンは完全自動判別)
# ==============================================================================
set -euo pipefail

# ------------------------------------------------------------------------------
# パラメータ設定
# ------------------------------------------------------------------------------
version="7.0"                      # Zabbix メジャーバージョン (8.0, 7.0, または 6.0)
dbengine="mysql"                   # DBエンジン: mysql (MariaDB) または postgresql (PostgreSQL)
enable_db_compression="true"       # DB圧縮チューニング: true または false
enable_timescaledb="false"         # TimescaleDB 構成: true または false (dbengine=postgresql 時のみ有効)

timezone="Asia\/Tokyo"             # フロントエンドのタイムゾーン (スラッシュはエスケープ)
agentname="zabbix-server"          # Zabbix Agent ホスト名
dbhost="localhost"                 # DB ホスト
dbname="zabbix"                    # DB 名
dbuser="zabbix"                    # DB ユーザー名
dbpassword="zabbix_password"       # DB パスワード (本番環境では変更してください)
encryption="unencrypted"           # 暗号化方式: unencrypted, psk, または cert

# 暗号化方式が psk の場合
pskid=""                           # Pre-Shared Key Identity

# 暗号化方式が cert の場合 (ダウンロード可能なURLを指定)
cafile=""                          # CA証明書 URL
certfile=""                        # Server証明書 URL
keyfile=""                         # 秘密鍵ファイル URL

# ------------------------------------------------------------------------------
# 1. CPU アーキテクチャ & Amazon Linux バージョンの完全自動判定
# ------------------------------------------------------------------------------
# CPU アーキテクチャ自動判定
RAW_ARCH=$(uname -m)
case "${RAW_ARCH}" in
  x86_64)
    ARCH="x86_64"
    ;;
  aarch64|arm64)
    ARCH="aarch64"
    ;;
  *)
    echo "Error: Unsupported architecture: ${RAW_ARCH}" >&2
    exit 1
    ;;
esac

# OS 自動判定 (Amazon Linux 2023 または Amazon Linux 2 のみ対象)
if [ -f /etc/os-release ]; then
  # shellcheck source=/dev/null
  . /etc/os-release
  if [ "${ID:-}" = "amzn" ]; then
    case "${VERSION_ID:-}" in
      2023*)
        amazonlinux="amzn2023"
        ;;
      2*)
        amazonlinux="amzn2"
        ;;
      *)
        echo "Error: Unsupported Amazon Linux version: ${VERSION_ID:-}" >&2
        exit 1
        ;;
    esac
  else
    echo "Error: Unsupported OS '${ID:-}'. This script only supports Amazon Linux (AL2023 / AL2)." >&2
    exit 1
  fi
elif grep -qi 'Amazon Linux release 2023' /etc/system-release 2>/dev/null; then
  amazonlinux="amzn2023"
elif grep -qi 'Amazon Linux release 2' /etc/system-release 2>/dev/null; then
  amazonlinux="amzn2"
else
  echo "Error: Unable to detect Amazon Linux version. This script only supports Amazon Linux (AL2023 / AL2)." >&2
  exit 1
fi

# Zabbix 8.0 動作要件のバリデーション
if [ "${version}" = "8.0" ]; then
  if [ "${amazonlinux}" != "amzn2023" ]; then
    echo "Error: Zabbix 8.0 requires Amazon Linux 2023 or later (Amazon Linux 2 is not supported)." >&2
    exit 1
  fi
  if [ "${dbengine}" = "mysql" ]; then
    echo "Note: Zabbix 8.0 requires MariaDB 10.11+ or MySQL 8.4 LTS+."
    echo "On Amazon Linux 2023 with local database, 'postgresql' (PostgreSQL 15+) is strongly recommended."
  fi
fi

echo "========================================================"
echo " Detected OS: ${amazonlinux} (${ARCH})"
echo " Target Zabbix Version: ${version}"
echo " Database Engine: ${dbengine}"
echo " DB Compression Tuning: ${enable_db_compression}"
echo " TimescaleDB Enabled: ${enable_timescaledb}"
echo "========================================================"

# ------------------------------------------------------------------------------
# 2. パッケージマネージャと公式リポジトリの登録
# ------------------------------------------------------------------------------
if [ "${amazonlinux}" = "amzn2023" ]; then
  PKG_MGR="dnf"
  ${PKG_MGR} update -y
  # 公式 Zabbix リポジトリ RPM のインストール
  rpm -Uvh --replacepkgs "https://repo.zabbix.com/zabbix/${version}/amazonlinux/2023/${ARCH}/zabbix-release-latest-${version}.amzn2023.noarch.rpm" || true
  ${PKG_MGR} clean all
elif [ "${amazonlinux}" = "amzn2" ]; then
  PKG_MGR="yum"
  ${PKG_MGR} update -y
  # AL2 の場合は EPEL および RHEL7 互換公式リポジトリを利用
  amazon-linux-extras install epel -y || true
  ${PKG_MGR} install -y epel-release || true
  rpm -Uvh --replacepkgs "https://repo.zabbix.com/zabbix/${version}/rhel/7/x86_64/zabbix-release-latest-${version}.el7.noarch.rpm" || true
  ${PKG_MGR} clean all
fi

# ------------------------------------------------------------------------------
# 3. データベースおよび Zabbix パッケージのインストール
# ------------------------------------------------------------------------------
COMMON_PKGS="zabbix-web zabbix-apache-conf zabbix-sql-scripts zabbix-agent httpd"

if [ "${dbengine}" = "mysql" ]; then
  if [ "${amazonlinux}" = "amzn2023" ]; then
    ${PKG_MGR} install -y mariadb105-server zabbix-server-mysql zabbix-web-mysql ${COMMON_PKGS}
  else
    amazon-linux-extras install -y lamp-mariadb10.2-php7.2 php7.2 || true
    ${PKG_MGR} install -y mariadb mariadb-server zabbix-server-mysql zabbix-web-mysql ${COMMON_PKGS}
  fi
elif [ "${dbengine}" = "postgresql" ]; then
  if [ "${amazonlinux}" = "amzn2023" ]; then
    ${PKG_MGR} install -y postgresql15-server zabbix-server-pgsql zabbix-web-pgsql ${COMMON_PKGS}
  else
    amazon-linux-extras install -y postgresql14 php7.2 || true
    ${PKG_MGR} install -y postgresql-server zabbix-server-pgsql zabbix-web-pgsql ${COMMON_PKGS}
  fi

  # TimescaleDB 拡張パッケージの導入 (希望時)
  if [ "${enable_timescaledb}" = "true" ]; then
    echo "Setting up TimescaleDB repository..."
    if [ "${amazonlinux}" = "amzn2023" ] && [ "${ARCH}" = "x86_64" ]; then
      curl -s https://packagecloud.io/install/repositories/timescale/timescaledb/script.rpm.sh | bash || true
      ${PKG_MGR} install -y timescaledb-2-postgresql-15 || true
    elif [ "${amazonlinux}" = "amzn2" ]; then
      curl -s https://packagecloud.io/install/repositories/timescale/timescaledb/script.rpm.sh | bash || true
      ${PKG_MGR} install -y timescaledb-2-postgresql-14 || true
    else
      echo "Note: TimescaleDB official RPM might not be available for ${amazonlinux} on ${ARCH}."
      echo "Proceeding with standard PostgreSQL with LZ4 compression."
    fi
  fi
else
  echo "Unsupported dbengine: ${dbengine}" >&2
  exit 1
fi

# ------------------------------------------------------------------------------
# 4. データベースの初期設定 & スキーマのインポート
# ------------------------------------------------------------------------------
# スキーマファイルの探索 (Zabbix 6.0/7.0/8.0 は zabbix-sql-scripts 配下)
SCHEMA_FILE=$(find /usr/share/zabbix-sql-scripts /usr/share/doc/zabbix-sql-scripts -name "server.sql.gz" 2>/dev/null | head -n 1 || true)
if [ -z "${SCHEMA_FILE}" ]; then
  SCHEMA_FILE=$(find /usr/share -name "server.sql.gz" 2>/dev/null | head -n 1 || true)
fi

if [ "${dbengine}" = "mysql" ]; then
  # InnoDB 圧縮設定の反映
  if [ "${enable_db_compression}" = "true" ]; then
    mkdir -p /etc/my.cnf.d
    cat <<EOF > /etc/my.cnf.d/zabbix_compression.cnf
[mysqld]
innodb_file_per_table = 1
EOF
  fi

  systemctl start mariadb.service
  systemctl enable mariadb.service

  # root ランダムパスワード生成
  vMySQLRootPasswd="$(cat /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 16)"
  echo "${vMySQLRootPasswd}" > /root/.mysql.secrets
  chmod 600 /root/.mysql.secrets

  # 初期 DB & ユーザー作成 (utf8mb4)
  mysql -u root <<EOF || true
ALTER USER 'root'@'localhost' IDENTIFIED BY '${vMySQLRootPasswd}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF

  cat <<EOF > /root/.my.cnf
[client]
host = localhost
user = root
password = "${vMySQLRootPasswd}"
EOF
  chmod 600 /root/.my.cnf

  mysql --defaults-file=/root/.my.cnf <<EOF
CREATE DATABASE ${dbname} CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER '${dbuser}'@'localhost' IDENTIFIED BY '${dbpassword}';
GRANT ALL PRIVILEGES ON ${dbname}.* TO '${dbuser}'@'localhost';
SET GLOBAL log_bin_trust_function_creators = 1;
FLUSH PRIVILEGES;
EOF

  # スキーマインポート
  if [ -n "${SCHEMA_FILE}" ] && [ -f "${SCHEMA_FILE}" ]; then
    zcat "${SCHEMA_FILE}" | mysql --defaults-file=/root/.my.cnf "${dbname}"
  fi

  mysql --defaults-file=/root/.my.cnf -e "SET GLOBAL log_bin_trust_function_creators = 0;"

  # MySQL / MariaDB 圧縮チューニングの適用
  if [ "${enable_db_compression}" = "true" ]; then
    echo "Applying InnoDB ROW_FORMAT=COMPRESSED table tuning..."
    mysql --defaults-file=/root/.my.cnf "${dbname}" <<'EOF' || true
ALTER TABLE history ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=8;
ALTER TABLE history_log ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=8;
ALTER TABLE history_str ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=8;
ALTER TABLE history_text ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=8;
ALTER TABLE history_uint ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=8;
ALTER TABLE events ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=8;
EOF
  fi

  # Zabbix Agent テンプレート用接続設定
  mkdir -p /var/lib/zabbix
  cat <<EOF > /var/lib/zabbix/.my.cnf
[client]
user = ${dbuser}
password = "${dbpassword}"
EOF
  chown zabbix:zabbix /var/lib/zabbix/.my.cnf 2>/dev/null || true
  chmod 600 /var/lib/zabbix/.my.cnf

elif [ "${dbengine}" = "postgresql" ]; then
  if [ ! -s "/var/lib/pgsql/data/PG_VERSION" ]; then
    postgresql-setup --initdb || true
  fi

  # pg_hba.conf でローカルTCP接続 (127.0.0.1/32, ::1/128) の ident 認証を scram-sha-256 に更新
  PG_HBA="/var/lib/pgsql/data/pg_hba.conf"
  if [ -f "${PG_HBA}" ]; then
    sed -i -E 's/(host\s+all\s+all\s+(127\.0\.0\.1\/32|::1\/128)\s+)ident/\1scram-sha-256/' "${PG_HBA}"
  fi

  # TimescaleDB preload 設定
  if [ "${enable_timescaledb}" = "true" ]; then
    PG_CONF="/var/lib/pgsql/data/postgresql.conf"
    if [ -f "${PG_CONF}" ]; then
      if grep -q "shared_preload_libraries" "${PG_CONF}"; then
        sed -i -E "s/^[# ]*shared_preload_libraries[[:space:]]*=.*/shared_preload_libraries = 'timescaledb'/" "${PG_CONF}"
      else
        echo "shared_preload_libraries = 'timescaledb'" >> "${PG_CONF}"
      fi
    fi
  fi

  systemctl start postgresql.service
  systemctl enable postgresql.service

  sudo -u postgres psql <<EOF
CREATE USER ${dbuser} WITH PASSWORD '${dbpassword}';
CREATE DATABASE ${dbname} OWNER ${dbuser};
EOF

  # スキーマインポート
  if [ -n "${SCHEMA_FILE}" ] && [ -f "${SCHEMA_FILE}" ]; then
    zcat "${SCHEMA_FILE}" | PGPASSWORD="${dbpassword}" psql -h localhost -U ${dbuser} -d ${dbname}
  fi

  # TimescaleDB 拡張の適用
  if [ "${enable_timescaledb}" = "true" ]; then
    echo "Enabling TimescaleDB extension and applying hypertable schema..."
    sudo -u postgres psql -d "${dbname}" -c "CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;" || true
    
    TIMESCALE_SCHEMA=$(find /usr/share/zabbix-sql-scripts /usr/share/doc/zabbix-sql-scripts -name "schema.sql" 2>/dev/null | grep "timescaledb" | head -n 1 || true)
    if [ -n "${TIMESCALE_SCHEMA}" ] && [ -f "${TIMESCALE_SCHEMA}" ]; then
      cat "${TIMESCALE_SCHEMA}" | PGPASSWORD="${dbpassword}" psql -h localhost -U ${dbuser} -d ${dbname} || true
    fi
  fi

  # PostgreSQL 圧縮チューニング (LZ4 + toast_tuple_target=128)
  if [ "${enable_db_compression}" = "true" ]; then
    echo "Applying PostgreSQL LZ4 and TOAST compression tuning..."
    sudo -u postgres psql -d "${dbname}" <<'EOF' || true
ALTER SYSTEM SET default_toast_compression = 'lz4';
ALTER SYSTEM SET max_wal_size = '256MB';
SELECT pg_reload_conf();

ALTER TABLE history_text SET (toast_tuple_target = 128);
ALTER TABLE history_text ALTER COLUMN value SET COMPRESSION lz4;
ALTER TABLE history_log  SET (toast_tuple_target = 128);
ALTER TABLE history_log  ALTER COLUMN value SET COMPRESSION lz4;
ALTER TABLE history_str  SET (toast_tuple_target = 128);
ALTER TABLE history_str  ALTER COLUMN value SET COMPRESSION lz4;
ALTER TABLE items        SET (toast_tuple_target = 128);
ALTER TABLE item_preproc SET (toast_tuple_target = 128);
ALTER TABLE events       SET (toast_tuple_target = 128);
ALTER TABLE auditlog     SET (toast_tuple_target = 128);
EOF
  fi
fi

# ------------------------------------------------------------------------------
# 5. Zabbix Server 設定 (/etc/zabbix/zabbix_server.conf)
# ------------------------------------------------------------------------------
sed -i -E "s/^[# ]*LogFileSize=.*/LogFileSize=10/" /etc/zabbix/zabbix_server.conf
sed -i -E "s/^[# ]*DBHost=.*/DBHost=${dbhost}/" /etc/zabbix/zabbix_server.conf
sed -i -E "s/^[# ]*DBName=.*/DBName=${dbname}/" /etc/zabbix/zabbix_server.conf
sed -i -E "s/^[# ]*DBUser=.*/DBUser=${dbuser}/" /etc/zabbix/zabbix_server.conf
sed -i -E "s/^[# ]*DBPassword=.*/DBPassword=${dbpassword}/" /etc/zabbix/zabbix_server.conf
sed -i -E "s/^[# ]*StartPollers=.*/StartPollers=10/" /etc/zabbix/zabbix_server.conf
sed -i -E "s/^[# ]*StartPollersUnreachable=.*/StartPollersUnreachable=3/" /etc/zabbix/zabbix_server.conf
sed -i -E "s/^[# ]*StartPingers=.*/StartPingers=5/" /etc/zabbix/zabbix_server.conf
sed -i -E "s/^[# ]*StartDiscoverers=.*/StartDiscoverers=3/" /etc/zabbix/zabbix_server.conf
sed -i -E "s/^[# ]*StartHTTPPollers=.*/StartHTTPPollers=3/" /etc/zabbix/zabbix_server.conf

# ------------------------------------------------------------------------------
# 6. Zabbix Agent 設定 (/etc/zabbix/zabbix_agentd.conf)
# ------------------------------------------------------------------------------
sed -i -E "s/^[# ]*LogFileSize=.*/LogFileSize=5/" /etc/zabbix/zabbix_agentd.conf
sed -i -E "s/^[# ]*Server=127.0.0.1/Server=127.0.0.1/" /etc/zabbix/zabbix_agentd.conf
sed -i -E "s/^[# ]*ServerActive=127.0.0.1/ServerActive=127.0.0.1/" /etc/zabbix/zabbix_agentd.conf
sed -i -E "s/^[# ]*Hostname=.*/Hostname=${agentname}/" /etc/zabbix/zabbix_agentd.conf
sed -i -E "s/^[# ]*RefreshActiveChecks=.*/RefreshActiveChecks=60/" /etc/zabbix/zabbix_agentd.conf
sed -i -E "s/^[# ]*AllowKey=system.run\[\*\]/AllowKey=system.run[*]/" /etc/zabbix/zabbix_agentd.conf || true

# 暗号化設定 (PSK)
if [ "${encryption}" = "psk" ]; then
  mkdir -p /etc/zabbix/tls
  openssl rand -hex 128 > /etc/zabbix/tls/.zabbix_agentd.psk
  chown zabbix:zabbix /etc/zabbix/tls/.zabbix_agentd.psk 2>/dev/null || true
  chmod 400 /etc/zabbix/tls/.zabbix_agentd.psk

  sed -i -E "s/^[# ]*TLSConnect=.*/TLSConnect=psk/" /etc/zabbix/zabbix_agentd.conf
  sed -i -E "s/^[# ]*TLSAccept=.*/TLSAccept=psk/" /etc/zabbix/zabbix_agentd.conf
  sed -i -E "s/^[# ]*TLSPSKIdentity=.*/TLSPSKIdentity=${pskid}/" /etc/zabbix/zabbix_agentd.conf
  sed -i -E "s/^[# ]*TLSPSKFile=.*/TLSPSKFile=\/etc\/zabbix\/tls\/.zabbix_agentd.psk/" /etc/zabbix/zabbix_agentd.conf
fi

# 暗号化設定 (Cert)
if [ "${encryption}" = "cert" ]; then
  mkdir -p /etc/zabbix/tls
  cd /etc/zabbix/tls
  if [ -n "${cafile}" ]; then wget -O zabbix_ca_file "${cafile}"; fi
  if [ -n "${certfile}" ]; then wget -O zabbix.crt "${certfile}"; fi
  if [ -n "${keyfile}" ]; then wget -O zabbix.key "${keyfile}"; fi
  chown -R zabbix:zabbix /etc/zabbix/tls 2>/dev/null || true
  chmod 400 /etc/zabbix/tls/* 2>/dev/null || true

  sed -i -E "s/^[# ]*TLSConnect=.*/TLSConnect=cert/" /etc/zabbix/zabbix_agentd.conf
  sed -i -E "s/^[# ]*TLSAccept=.*/TLSAccept=cert/" /etc/zabbix/zabbix_agentd.conf
  sed -i -E "s/^[# ]*TLSCAFile=.*/TLSCAFile=\/etc\/zabbix\/tls\/zabbix_ca_file/" /etc/zabbix/zabbix_agentd.conf
  sed -i -E "s/^[# ]*TLSCertFile=.*/TLSCertFile=\/etc\/zabbix\/tls\/zabbix.crt/" /etc/zabbix/zabbix_agentd.conf
  sed -i -E "s/^[# ]*TLSKeyFile=.*/TLSKeyFile=\/etc\/zabbix\/tls\/zabbix.key/" /etc/zabbix/zabbix_agentd.conf
fi

# ------------------------------------------------------------------------------
# 7. Web フロントエンド / PHP-FPM 設定
# ------------------------------------------------------------------------------
if [ -f /etc/php-fpm.d/zabbix.conf ]; then
  sed -i -E "s/^[; ]*php_value\[date\.timezone\] = .*/php_value[date.timezone] = ${timezone}/" /etc/php-fpm.d/zabbix.conf
fi
if [ -f /etc/php.ini ]; then
  sed -i -E "s/^[; ]*date\.timezone = .*/date.timezone = ${timezone}/" /etc/php.ini
fi

# ------------------------------------------------------------------------------
# 8. サービスの起動 & 自動起動登録
# ------------------------------------------------------------------------------
systemctl enable --now httpd.service || true
systemctl enable --now php-fpm.service || true
systemctl enable --now zabbix-server.service
systemctl enable --now zabbix-agent.service

echo "Zabbix Server installation completed successfully."