#!/bin/bash
# ==============================================================================
# init: database — 建库授权（仅首启空数据目录时由官方 entrypoint 执行）
# ==============================================================================
# 幂等性说明: docker-entrypoint-initdb.d 只在数据目录为空的首启运行；
# 重复 up 不会重跑，重置需删数据目录（有破坏性，见运维手册）。
# 口令经 compose environment 注入（POSTGRES_USER 是超级管理员 postgres）。
# ==============================================================================
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
  -- ZITADEL（运维侧 IdP，stacks/zero-trust）
  CREATE ROLE zitadel LOGIN PASSWORD '${ZITADEL_DB_PASSWORD}';
  CREATE DATABASE zitadel OWNER zitadel;

  -- Casdoor（租户侧 IdP，stacks/casdoor；--createDatabase=true 会自建表）
  CREATE ROLE casdoor LOGIN PASSWORD '${CASDOOR_DB_PASSWORD}';
  CREATE DATABASE casdoor OWNER casdoor;

  -- OPIC 唯一业务库：全部能力中心共用（用户规则 2026-10-01：单实例 opicdb，每中心一个 schema）
  CREATE DATABASE opicdb OWNER ${POSTGRES_USER};
EOSQL

# 23 个中心 schema（域码小写），属主 opicdb_owner；第二步各中心上线时按域发登录角色
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" -d opicdb <<-EOSQL
  CREATE ROLE opicdb_owner NOLOGIN;
  CREATE SCHEMA osec AUTHORIZATION opicdb_owner;  CREATE SCHEMA osys AUTHORIZATION opicdb_owner;
  CREATE SCHEMA oarc AUTHORIZATION opicdb_owner;  CREATE SCHEMA odbs AUTHORIZATION opicdb_owner;
  CREATE SCHEMA oreg AUTHORIZATION opicdb_owner;  CREATE SCHEMA ocrt AUTHORIZATION opicdb_owner;
  CREATE SCHEMA ovpn AUTHORIZATION opicdb_owner;  CREATE SCHEMA oign AUTHORIZATION opicdb_owner;
  CREATE SCHEMA oclc AUTHORIZATION opicdb_owner;  CREATE SCHEMA oosc AUTHORIZATION opicdb_owner;
  CREATE SCHEMA oadd AUTHORIZATION opicdb_owner;  CREATE SCHEMA oast AUTHORIZATION opicdb_owner;
  CREATE SCHEMA ousr AUTHORIZATION opicdb_owner;  CREATE SCHEMA opip AUTHORIZATION opicdb_owner;
  CREATE SCHEMA oapp AUTHORIZATION opicdb_owner;  CREATE SCHEMA ocsc AUTHORIZATION opicdb_owner;
  CREATE SCHEMA oapf AUTHORIZATION opicdb_owner;  CREATE SCHEMA oopr AUTHORIZATION opicdb_owner;
  CREATE SCHEMA odat AUTHORIZATION opicdb_owner;  CREATE SCHEMA omdl AUTHORIZATION opicdb_owner;
  CREATE SCHEMA oknb AUTHORIZATION opicdb_owner;  CREATE SCHEMA omon AUTHORIZATION opicdb_owner;
  CREATE SCHEMA ocmp AUTHORIZATION opicdb_owner;
  GRANT USAGE ON SCHEMA public TO opicdb_owner;
EOSQL

echo "[init] opicdb 就绪：23 个中心 schema（opicdb_owner 属主）"

echo "[init] 数据库就绪: zitadel / casdoor / opicdb"
