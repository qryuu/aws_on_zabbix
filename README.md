# aws_on_zabbix

AWS 上での Zabbix 運用・自動構築スクリプト集  
Automation and operation scripts for Zabbix on AWS (Amazon Linux 2023 / Amazon Linux 2)

---

## 主な特徴 / Features

- **OS・アーキテクチャの完全自動判別**:
  - **OS 自動判別**: Amazon Linux 2023 (`amzn2023`) および Amazon Linux 2 (`amzn2`) を `/etc/os-release` から自動識別（手動指定不要、Amazon Linux 以外は安全に終了）
  - **CPU アーキテクチャ自動判別**: `x86_64` (Intel/AMD) および `aarch64` (AWS Graviton) を自動検出
- **Zabbix 公式リポジトリ対応**: `repo.zabbix.com` から公式 RPM パッケージを取得
- **DB エンジン選択**: MySQL (MariaDB) または PostgreSQL をパラメータで選択可能
- **DB 圧縮チューニング（標準搭載）**:
  - **PostgreSQL**: `default_toast_compression = 'lz4'` および 短文テキスト圧縮閾値引き下げ (`toast_tuple_target = 128`) を適用。`history_text`, `history_log`, `history_str`, `items`, `events` 等のテキストデータを初期投入時から LZ4 圧縮し、ストレージ消費を大幅に抑制
  - **MySQL (MariaDB)**: `history`, `history_uint`, `history_str`, `history_text`, `history_log`, `events` テーブルに `ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=8` を適用
- **TimescaleDB 構成の選択対応**:
  - 新規初期構築時に時系列ハイパーテーブルおよび列指向圧縮（Delta-of-Delta / Gorilla XOR）を活用したい場合、`enable_timescaledb="true"` を指定可能
- **Zabbix 8.0 LTS (先行対応) / 7.0 LTS / 6.0 LTS 対応**: 最新の安定版 LTS およびリリース予定の次期 LTS バージョンに対応

---

## スクリプト一覧 / Scripts

### 1. `/UserData/Launch-ZabbixServer-on-AmazonLinux.sh`

Amazon Linux 2023 / Amazon Linux 2 に Zabbix Server および Web フロントエンドを自動構築します。  
EC2 インスタンスの新規ローンチ時に **UserData** に投入してください。OS や CPU アーキテクチャは自動判別されます。

Automatically deploys Zabbix Server and Web frontend on Amazon Linux 2023 or Amazon Linux 2.  
Provide this script into **UserData** when launching an EC2 instance. OS and CPU architecture are detected automatically.

#### 主要パラメータ / Main Parameters

| パラメータ | デフォルト値 | 説明 |
|---|---|---|
| `version` | `7.0` | Zabbix バージョン (`8.0`, `7.0`, または `6.0`) |
| `dbengine` | `mysql` | DB エンジン (`mysql` または `postgresql`) |
| `enable_db_compression` | `true` | DB 圧縮チューニングの有効化 (`true` または `false`) |
| `enable_timescaledb` | `false` | TimescaleDB 構成の有効化 (`true` または `false`、PostgreSQL 時のみ) |
| `timezone` | `Asia\/Tokyo` | PHP フロントエンドのタイムゾーン |
| `agentname` | `zabbix-server` | Zabbix Agent ホスト名 |
| `dbname` | `zabbix` | データベース名 |
| `dbuser` | `zabbix` | データベースユーザー名 |
| `dbpassword` | `zabbix_password` | データベースパスワード |
| `encryption` | `unencrypted` | 通信暗号化方式 (`unencrypted`, `psk`, `cert`) |

#### OS・アーキテクチャ サポートマトリクス / Support Matrix

Zabbix 公式リポジトリ（`repo.zabbix.com`）の提供仕様および AWS 実環境でのテストに基づくサポート状況です：

| コンポーネント | Amazon Linux 2023 (`x86_64` / `aarch64`) | Amazon Linux 2 (`x86_64`) | Amazon Linux 2 (`aarch64`) |
|---|:---:|:---:|:---:|
| **Zabbix Server 8.0 / 7.0 / 6.0** | **対応** (推奨) | 非対応 (公式未提供) | 非対応 (公式未提供) |
| **Zabbix Proxy 8.0 / 7.0** | **対応** | 非対応 | 非対応 |
| **Zabbix Proxy 6.0** | **対応** | **対応** | 非対応 |
| **Zabbix Agent / Agent 2** | **対応** | **対応** | 非対応 |

> [!IMPORTANT]
> **Zabbix Server 構築時の注意**:  
> Zabbix 6.0 LTS 以降、公式リポジトリでは RHEL 7 / Amazon Linux 2 向けの Server パッケージは提供されておらず（Proxy および Agent のみ提供）、**Zabbix Server の構築には Amazon Linux 2023 が必須** となります。

#### Zabbix 8.0 LTS を選択する場合の留意点
- **OS要件**: **Amazon Linux 2023 (AL2023) が必須** です。
- **DB要件**: MariaDB 10.11+ / MySQL 8.4 LTS+ / PostgreSQL 15.0+ が必須です。AL2023 のローカル DB では **`postgresql` (PostgreSQL 15)** の選択を強く推奨します。
- **PHP要件**: PHP 8.2〜8.5 が必須（AL2023 標準で対応）。

---

### 2. `/UserData/Launch-ZabbixProxy-on-AmazonLinux.sh`

Amazon Linux 2023 / Amazon Linux 2 に Zabbix Proxy を自動構築します。  
EC2 インスタンスのローンチ時に **UserData** に投入してください。

#### 主要パラメータ / Main Parameters

| パラメータ | デフォルト値 | 説明 |
|---|---|---|
| `version` | `7.0` | Zabbix バージョン (`8.0`, `7.0`, または `6.0`) |
| `dbengine` | `mysql` | DB エンジン (`mysql` または `postgresql`) |
| `enable_db_compression` | `true` | DB 圧縮チューニング (`true` または `false`) |
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

#### 主要パラメータ / Main Parameters

| パラメータ | デフォルト値 | 説明 |
|---|---|---|
| `dbengine` | `mysql` | DB エンジン (`mysql` または `postgresql`) |
| `enable_db_compression` | `true` | RDS 側テーブル圧縮チューニング (`true` または `false`) |
| `rdshost` | (必須) | RDS エンドポイント (FQDN) |
| `rdsuser` | `admin` | RDS マスターユーザー名 |
| `rdspassword` | (必須) | RDS マスターパスワード |
| `dbname` | `zabbix` | 移行先データベース名 |
| `dbuser` | `zabbix` | 移行先 Zabbix 用ユーザー名 |
| `dbpassword` | `zabbix_password` | 移行先 Zabbix 用パスワード |

> [!NOTE]
> **RDS 移行スクリプトの自動最適化機能**:
> - **MySQL 8.0 / 8.4 LTS 互換性自動サニタイズ**: MariaDB のダンプに含まれる廃止された `NO_AUTO_CREATE_USER` や、RDS で権限エラーとなるトリガーの `DEFINER` 句を自動除去して安全にリストアします。
> - **PostgreSQL 移行時の冪等性**: RDS 側にデータベースが既に存在する場合でも停止せず、オーナー権限の自動調整を行いスムーズに移行を完了します。
> - **データ整合性保護**: ダンプ取得前に Zabbix Server を自動停止し、移行中のデータ不整合を防止します。

---

### 4. アップデートスクリプト / Update Scripts

- **`/Scripts/for_8.0_update.sh`**: Amazon Linux 2023 上の Zabbix Server を 8.0 LTS にアップデートします。
- **`/Scripts/for_7.0_update.sh`**: Amazon Linux 2023 上の Zabbix Server を 7.0 LTS にアップデートします。
- **`/Scripts/for_6.0_update.sh`**: Amazon Linux 2 / Amazon Linux 2023 上の Zabbix Server を 6.0 LTS にアップデートします。
- **`/Scripts/for_5.0_update.sh`**: Amazon Linux 2 上の既存 Zabbix 4.0 環境を 5.0 LTS にアップデートします。

---

## ライセンス / License

MIT License
