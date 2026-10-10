#!/bin/bash
# ==============================================================================
# Zabbix-for-RDS.sh
# 
# EC2 ローカル DB で稼働している Zabbix Server のデータを AWS RDS (MySQL / PostgreSQL)
# へ自動移行し、接続先を切り替える EC2 UserData スクリプト
# ==============================================================================
set -euo pipefail

# ------------------------------------------------------------------------------
# パラメータ設定
# ------------------------------------------------------------------------------
dbengine="mysql"                   # DBエンジン: mysql または postgresql
enable_db_compression="true"       # DB圧縮チューニング: true または false
rdshost=""                         # RDS エンドポイント (FQDN)
rdsuser="admin"                    # RDS マスターユーザー名
rdspassword=""                     # RDS マスターパスワード
dbname="zabbix"                    # 移行先 DB 名
dbuser="zabbix"                    # 移行先 Zabbix 用 DB ユーザー名
dbpassword="zabbix_password"       # 移行先 Zabbix 用 DB パスワード

if [ -z "${rdshost}" ] || [ -z "${rdspassword}" ]; then
  echo "Error: rdshost and rdspassword must be specified." >&2
  exit 1
fi

echo "Starting Zabbix DB migration to RDS (${rdshost}) for ${dbengine}..."

# ------------------------------------------------------------------------------
# 1. 既存の設定値を取得
# ------------------------------------------------------------------------------
get_conf_val() {
  local key="$1"
  local file="/etc/zabbix/zabbix_server.conf"
  grep -E "^[# ]*${key}=" "${file}" 2>/dev/null | head -n 1 | sed -E "s/^[# ]*${key}=//" || echo ""
}

confdbhost=$(get_conf_val "DBHost")
[ -z "${confdbhost}" ] && confdbhost="localhost"
confdbname=$(get_conf_val "DBName")
[ -z "${confdbname}" ] && confdbname="zabbix"
confdbuser=$(get_conf_val "DBUser")
[ -z "${confdbuser}" ] && confdbuser="zabbix"
confdbpassword=$(get_conf_val "DBPassword")

# ------------------------------------------------------------------------------
# 2. データベースダンプ & RDS へのリストア
# ------------------------------------------------------------------------------
# 移行中のデータ不整合・新規書き込みを防ぐため、事前に Zabbix Server を停止
systemctl stop zabbix-server.service || true

if [ "${dbengine}" = "mysql" ]; then
  systemctl start mariadb.service || true

  # ローカル接続用 my.cnf
  cat <<EOF > /root/.my_local.cnf
[client]
host = ${confdbhost}
user = ${confdbuser}
password = "${confdbpassword}"
EOF
  chmod 600 /root/.my_local.cnf

  # RDS 接続用 my.cnf
  cat <<EOF > /root/.my_rds.cnf
[client]
host = ${rdshost}
user = ${rdsuser}
password = "${rdspassword}"
EOF
  chmod 600 /root/.my_rds.cnf

  # ローカルDBからダンプ
  mysqldump --defaults-file=/root/.my_local.cnf \
    --single-transaction \
    --quick \
    --default-character-set=utf8mb4 \
    "${confdbname}" > /tmp/zabbix_backup.sql

  # RDS 上にデータベース & ユーザー作成
  mysql --defaults-file=/root/.my_rds.cnf <<EOF
CREATE DATABASE IF NOT EXISTS ${dbname} CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS '${dbuser}'@'%' IDENTIFIED BY '${dbpassword}';
GRANT ALL PRIVILEGES ON ${dbname}.* TO '${dbuser}'@'%';
SET GLOBAL log_bin_trust_function_creators = 1;
FLUSH PRIVILEGES;
EOF

  # RDS へリストア
  mysql --defaults-file=/root/.my_rds.cnf "${dbname}" < /tmp/zabbix_backup.sql

  # 圧縮チューニングの適用
  if [ "${enable_db_compression}" = "true" ]; then
    echo "Applying InnoDB table compression tuning on RDS MySQL..."
    mysql --defaults-file=/root/.my_rds.cnf "${dbname}" <<'EOF' || true
ALTER TABLE history ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=8;
ALTER TABLE history_log ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=8;
ALTER TABLE history_str ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=8;
ALTER TABLE history_text ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=8;
ALTER TABLE history_uint ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=8;
ALTER TABLE events ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=8;
EOF
  fi

  mysql --defaults-file=/root/.my_rds.cnf -e "SET GLOBAL log_bin_trust_function_creators = 0;" || true

  # 一時ファイル削除
  rm -f /tmp/zabbix_backup.sql /root/.my_local.cnf /root/.my_rds.cnf

  # ローカル DB 停止 & 無効化
  systemctl stop mariadb.service || true
  systemctl disable mariadb.service || true

elif [ "${dbengine}" = "postgresql" ]; then
  systemctl start postgresql.service || true

  # ローカルDBからダンプ
  sudo -u postgres pg_dump -d "${confdbname}" -F p > /tmp/zabbix_backup.sql

  # RDS 上にユーザー作成 & 権限付与
  PGPASSWORD="${rdspassword}" psql -h "${rdshost}" -U "${rdsuser}" -d postgres <<EOF
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${dbuser}') THEN
    CREATE USER ${dbuser} WITH PASSWORD '${dbpassword}';
  END IF;
END
\$\$;
GRANT ${dbuser} TO ${rdsuser};
EOF

  # RDS 上のデータベース存在チェック & 作成/オーナー設定
  db_exists=$(PGPASSWORD="${rdspassword}" psql -h "${rdshost}" -U "${rdsuser}" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='${dbname}'" 2>/dev/null || echo "0")
  if [ "${db_exists}" != "1" ]; then
    PGPASSWORD="${rdspassword}" psql -h "${rdshost}" -U "${rdsuser}" -d postgres -c "CREATE DATABASE ${dbname} OWNER ${dbuser};"
  else
    PGPASSWORD="${rdspassword}" psql -h "${rdshost}" -U "${rdsuser}" -d postgres -c "ALTER DATABASE ${dbname} OWNER TO ${dbuser};"
  fi

  # RDS へリストア
  PGPASSWORD="${dbpassword}" psql -h "${rdshost}" -U "${dbuser}" -d "${dbname}" < /tmp/zabbix_backup.sql

  # 圧縮チューニングの適用 (LZ4 + toast_tuple_target=128)
  if [ "${enable_db_compression}" = "true" ]; then
    echo "Applying PostgreSQL LZ4 and TOAST compression tuning on RDS..."
    PGPASSWORD="${dbpassword}" psql -h "${rdshost}" -U "${dbuser}" -d "${dbname}" <<'EOF' || true
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

  # 一時ファイル削除
  rm -f /tmp/zabbix_backup.sql

  # ローカル DB 停止 & 無効化
  systemctl stop postgresql.service || true
  systemctl disable postgresql.service || true
fi

# ------------------------------------------------------------------------------
# 3. Zabbix Server 設定ファイルの接続先切り替え
# ------------------------------------------------------------------------------
sed -i -E "s/^[# ]*DBHost=.*/DBHost=${rdshost}/" /etc/zabbix/zabbix_server.conf
sed -i -E "s/^[# ]*DBName=.*/DBName=${dbname}/" /etc/zabbix/zabbix_server.conf
sed -i -E "s/^[# ]*DBUser=.*/DBUser=${dbuser}/" /etc/zabbix/zabbix_server.conf
sed -i -E "s/^[# ]*DBPassword=.*/DBPassword=${dbpassword}/" /etc/zabbix/zabbix_server.conf

# ------------------------------------------------------------------------------
# 4. Zabbix Web フロントエンド設定ファイルの接続先切り替え
# ------------------------------------------------------------------------------
WEB_CONF="/etc/zabbix/web/zabbix.conf.php"
if [ -f "${WEB_CONF}" ]; then
  sed -i -E "s/\\\$DB\\['SERVER'\\][[:space:]]*=.*/\\\$DB['SERVER']   = '${rdshost}';/" "${WEB_CONF}"
  sed -i -E "s/\\\$DB\\['DATABASE'\\][[:space:]]*=.*/\\\$DB['DATABASE'] = '${dbname}';/" "${WEB_CONF}"
  sed -i -E "s/\\\$DB\\['USER'\\][[:space:]]*=.*/\\\$DB['USER']     = '${dbuser}';/" "${WEB_CONF}"
  sed -i -E "s/\\\$DB\\['PASSWORD'\\][[:space:]]*=.*/\\\$DB['PASSWORD'] = '${dbpassword}';/" "${WEB_CONF}"
fi

# ------------------------------------------------------------------------------
# 5. Zabbix 監視用テンプレート設定の更新
# ------------------------------------------------------------------------------
if [ "${dbengine}" = "mysql" ]; then
  mkdir -p /var/lib/zabbix
  cat <<EOF > /var/lib/zabbix/.my.cnf
[client]
host = ${rdshost}
user = ${dbuser}
password = "${dbpassword}"
EOF
  chown zabbix:zabbix /var/lib/zabbix/.my.cnf 2>/dev/null || true
  chmod 600 /var/lib/zabbix/.my.cnf
fi

# ------------------------------------------------------------------------------
# 6. サービス再起動で新しい接続先を反映
# ------------------------------------------------------------------------------
systemctl restart zabbix-server.service || true
systemctl restart httpd.service || true
systemctl restart php-fpm.service || true

echo "Migration to RDS completed successfully."