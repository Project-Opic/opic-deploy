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

  -- OPIC 统一业务库（schema 前缀隔离，禁止 AutoMigrate；migrations/ 纪律见平台规则）
  CREATE DATABASE opicdb OWNER ${POSTGRES_USER};
EOSQL

echo "[init] 数据库就绪: zitadel / casdoor / opicdb"
