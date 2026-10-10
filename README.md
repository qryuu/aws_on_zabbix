# aws_on_zabbix

AWS 上での Zabbix 運用・自動構築スクリプト集  
Automation and operation scripts for Zabbix on AWS (Amazon Linux 2023 / Amazon Linux 2)

---

## 主な特徴 / Features

- **OS・アーキテクチャの完全自動判別**:
  - **OS 自動判別**: Amazon Linux 2023 (`amzn2023`) および Amazon Linux 2 (`amzn2`) を `/etc/os-release` から自動識別（手動パラメータ指定不要、Amazon Linux 以外は安全に終了）
  - **CPU アーキテクチャ自動判別**: `x86_64` (Intel/AMD) および `aarch64` (AWS Graviton) を自動検出
- **Zabbix 公式リポジトリ対応**: `repo.zabbix.com` から公式 RPM パッケージを取得
- **DB エンジン選択**: MySQL (MariaDB) または PostgreSQL をパラメータで選択可能
- **Zabbix 6.0 LTS / 7.0 LTS 対応**: 最新の安定版 LTS バージョンに対応

---

## スクリプト一覧 / Scripts

### 1. `/UserData/Launch-ZabbixServer-on-AmazonLinux.sh`

Amazon Linux 2023 / Amazon Linux 2 に Zabbix Server および Web フロントエンドを自動構築します。  
EC2 インスタンスの新規ローンチ時に **UserData** に投入してください。OS や CPU アーキテクチャは自動判別されるため、パラメータ指定は不要です。

Automatically deploys Zabbix Server and Web frontend on Amazon Linux 2023 or Amazon Linux 2.  
Provide this script into **UserData** when launching an EC2 instance. OS and CPU architecture are detected automatically.

#### 主要パラメータ / Main Parameters

| パラメータ | デフォルト値 | 説明 |
|---|---|---|
| `version` | `7.0` | Zabbix バージョン (`7.0` または `6.0`) |
| `dbengine` | `mysql` | DB エンジン (`mysql` または `postgresql`) |
| `timezone` | `Asia\/Tokyo` | PHP フロントエンドのタイムゾーン |
| `agentname` | `zabbix-server` | Zabbix Agent ホスト名 |
| `dbname` | `zabbix` | データベース名 |
| `dbuser` | `zabbix` | データベースユーザー名 |
| `dbpassword` | `zabbix_password` | データベースパスワード |
| `encryption` | `unencrypted` | 通信暗号化方式 (`unencrypted`, `psk`, `cert`) |

---

### 2. `/UserData/Launch-ZabbixProxy-on-AmazonLinux.sh`

Amazon Linux 2023 / Amazon Linux 2 に Zabbix Proxy を自動構築します。  
EC2 インスタンスのローンチ時に **UserData** に投入してください。

Automatically deploys Zabbix Proxy on Amazon Linux 2023 or Amazon Linux 2.  
Provide this script into **UserData** when launching an EC2 instance.

#### 主要パラメータ / Main Parameters

| パラメータ | デフォルト値 | 説明 |
|---|---|---|
| `version` | `7.0` | Zabbix バージョン (`7.0` または `6.0`) |
| `dbengine` | `mysql` | DB エンジン (`mysql` または `postgresql`) |
| `proxyname` | `zabbix-proxy` | Zabbix Proxy ホスト名 |
| `server` | `10.0.0.10` | 接続先 Zabbix Server の IP または FQDN |
| `dbname` | `zabbix_proxy` | Proxy 用データベース名 |
| `dbuser` | `zabbix` | データベースユーザー名 |
| `dbpassword` | `zabbix_password` | データベースパスワード |
| `encryption` | `unencrypted` | 通信暗号化方式 (`unencrypted`, `psk`, `cert`) |

---

### 3. `/UserData/Zabbix-for-RDS.sh`

EC2 ローカル DB (MySQL / PostgreSQL) で稼働している Zabbix Server のデータを、AWS RDS (Amazon Aurora / RDS MySQL / RDS PostgreSQL) へ自動移行し、接続先を切り替えます。  
既存の EC2 から作成した AMI を新しくローンチする際、UserData に投入して実行します。

Automatically migrates local Zabbix database to AWS RDS (MySQL / PostgreSQL) and switches Zabbix Server and Web frontend configuration to point to RDS.  
Run this script via UserData when launching a new EC2 instance from an existing AMI.

#### 主要パラメータ / Main Parameters

| パラメータ | デフォルト値 | 説明 |
|---|---|---|
| `dbengine` | `mysql` | DB エンジン (`mysql` または `postgresql`) |
| `rdshost` | (必須) | RDS エンドポイント (FQDN) |
| `rdsuser` | `admin` | RDS マスターユーザー名 |
| `rdspassword` | (必須) | RDS マスターパスワード |
| `dbname` | `zabbix` | 移行先データベース名 |
| `dbuser` | `zabbix` | 移行先 Zabbix 用ユーザー名 |
| `dbpassword` | `zabbix_password` | 移行先 Zabbix 用パスワード |

---

### 4. アップデートスクリプト / Update Scripts

- **`/Scripts/for_7.0_update.sh`**: Amazon Linux 2023 上の Zabbix Server を 7.0 LTS にアップデートします。
- **`/Scripts/for_6.0_update.sh`**: Amazon Linux 2 / Amazon Linux 2023 上の Zabbix Server を 6.0 LTS にアップデートします。
- **`/Scripts/for_5.0_update.sh`**: Amazon Linux 2 上の既存 Zabbix 4.0 環境を 5.0 LTS にアップデートします。

---

## ライセンス / License

MIT License
