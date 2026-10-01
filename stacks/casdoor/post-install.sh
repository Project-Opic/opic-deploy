#!/usr/bin/env bash
# ==============================================================================
# post-install: casdoor — 等待首启建表完成并验证 HTTP 可达
# ==============================================================================
set -euo pipefail

STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${STACK_DIR}/../.." && pwd)"

if [[ -f "${ROOT_DIR}/.env" ]]; then
  set -a; # shellcheck disable=SC1091
  source "${ROOT_DIR}/.env"; set +a
else
  echo "[FAIL] 未找到 ${ROOT_DIR}/.env" >&2
  exit 1
fi

HTTP_PORT="${CASDOOR_HTTP_PORT:-8000}"

echo "── 校验 Casdoor（租户侧 IdP）────────────────────────────────────────────"

# 等待 HTTP 就绪（首启含建表，上限 3 分钟）
for i in $(seq 1 45); do
  CODE="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${HTTP_PORT}/" 2>/dev/null || true)"
  if [[ "${CODE}" == "200" || "${CODE}" == "302" ]]; then
    echo "  [OK] HTTP → ${CODE}（首启建表完成）"
    break
  fi
  if [[ "${i}" -eq 45 ]]; then
    echo "  [FAIL] Casdoor 3 分钟内未就绪（最后 code=${CODE}），请查看：docker logs opic-casdoor" >&2
    exit 1
  fi
  sleep 4
done

# 校验数据库表已建立（经统一 PG 查 casdoor 库）
TBL="$(docker exec opic-pg psql -U postgres -d casdoor -tAc \
  "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'" 2>/dev/null || echo 0)"
if [[ "${TBL}" -gt 0 ]]; then
  echo "  [OK] casdoor 库已建表（public schema ${TBL} 张表）"
else
  echo "  [FAIL] casdoor 库无表 —— 建库连接失败？请核对 .env 的 CASDOOR_DB_PASSWORD" >&2
  exit 1
fi

echo
echo "── 接入信息 ────────────────────────────────────────────────────────────"
echo "  登录入口   : http://<host>:${HTTP_PORT}"
echo "  默认管理员 : admin / 123 —— ⚠ 首登后必须改口令（运维手册 §安全基线）"
echo "  口令位置   : .env 的 CASDOOR_DB_PASSWORD（本脚本不回显）"
