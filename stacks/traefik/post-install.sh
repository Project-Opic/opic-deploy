#!/usr/bin/env bash
# ==============================================================================
# post-install: traefik — 校验壳与 dashboard
# ==============================================================================
set -euo pipefail

STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${STACK_DIR}/../.." && pwd)"

if [[ -f "${ROOT_DIR}/.env" ]]; then
  set -a; # shellcheck disable=SC1091
  source "${ROOT_DIR}/.env"; set +a
fi

WEB_PORT="${TRAEFIK_WEB_PORT:-80}"
DASH_PORT="${TRAEFIK_DASHBOARD_PORT:-8088}"

echo "── 校验 Traefik 壳 ──────────────────────────────────────────────────────"

for i in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${WEB_PORT}/ping" >/dev/null 2>&1; then
    echo "  [OK] /ping → 200"
    break
  fi
  if [[ "${i}" -eq 30 ]]; then
    echo "  [FAIL] Traefik 60 秒内未就绪，请查看：docker logs opic-traefik" >&2
    exit 1
  fi
  sleep 2
done

if curl -fsS "http://127.0.0.1:${DASH_PORT}/api/http/routers" >/dev/null 2>&1; then
  ROUTERS="$(curl -fsS "http://127.0.0.1:${DASH_PORT}/api/http/routers" 2>/dev/null | grep -o '"entryPoints"' | wc -l | tr -d ' ')"
  echo "  [OK] dashboard API 可用（当前 routers 记录数：${ROUTERS}）"
else
  echo "  [WARN] dashboard API 不可达（若生产关闭 api.insecure 属预期）"
fi

echo
echo "── 接入信息 ────────────────────────────────────────────────────────────"
echo "  HTTP 入口   : http://<host>:${WEB_PORT}"
echo "  dashboard   : http://<host>:${DASH_PORT}/dashboard/"
echo "  路由声明方式: 各 stack compose 的 traefik labels（exposedByDefault=false）"
