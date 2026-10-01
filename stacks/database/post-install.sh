#!/usr/bin/env bash
# ==============================================================================
# post-install: database — 校验统一 PostgreSQL 与建库授权
# ==============================================================================
set -euo pipefail

STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${STACK_DIR}/../.." && pwd)"

if [[ -f "${ROOT_DIR}/.env" ]]; then
  set -a; # shellcheck disable=SC1091
  source "${ROOT_DIR}/.env"; set +a
else
  echo "[WARN] 未找到 ${ROOT_DIR}/.env —— 使用默认值"
fi

echo "── 校验统一 PostgreSQL ──────────────────────────────────────────────────"

# 等待健康
for i in $(seq 1 30); do
  if docker exec opic-pg pg_isready -U postgres >/dev/null 2>&1; then
    echo "  [OK] pg_isready 通过"
    break
  fi
  if [[ "${i}" -eq 30 ]]; then
    echo "  [FAIL] PostgreSQL 60 秒内未就绪，请查看：docker logs opic-pg" >&2
    exit 1
  fi
  sleep 2
done

# 校验建库授权（zitadel / casdoor / opicdb）
for db in zitadel casdoor opicdb; do
  if docker exec opic-pg psql -U postgres -tAc \
    "SELECT 1 FROM pg_database WHERE datname='${db}'" | grep -q 1; then
    echo "  [OK] 数据库 ${db} 已就绪"
  else
    echo "  [FAIL] 数据库 ${db} 缺失（init 脚本未执行？数据目录是否残留旧实例？）" >&2
    exit 1
  fi
done

# 校验 opicdb 的 23 个中心 schema（用户规则 2026-10-01）
SCHEMAS="$(docker exec opic-pg psql -U postgres -d opicdb -tAc \
  "SELECT count(*) FROM information_schema.schemata WHERE schema_owner='opicdb_owner'" 2>/dev/null || echo 0)"
if [[ "${SCHEMAS}" -eq 23 ]]; then
  echo "  [OK] opicdb 含 23 个中心 schema（opicdb_owner 属主）"
else
  echo "  [FAIL] opicdb 中心 schema 数=${SCHEMAS}（应为 23，init 脚本未生效？）" >&2
  exit 1
fi

PG_PORT="${DATABASE_PG_PORT:-}"
echo
echo "── 接入信息 ────────────────────────────────────────────────────────────"
echo "  容器内 DSN : postgresql://opic-pg:5432/<db>"
echo "  宿主排障   : docker exec -it opic-pg psql -U postgres"
if [[ -n "${PG_PORT}" ]]; then
  echo "  宿主端口   : ${PG_PORT}（DEV 排障映射；生产不映射）"
fi
echo "  管理口令   : 见 .env 的 PG_ADMIN_PASSWORD（本脚本不回显）"
