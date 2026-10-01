#!/usr/bin/env bash
# ==============================================================================
# post-install: registry — Harbor 健康验收
# ==============================================================================
set -euo pipefail

STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${STACK_DIR}/../.." && pwd)"

if [[ -f "${ROOT_DIR}/.env" ]]; then
  set -a; # shellcheck disable=SC1091
  source "${ROOT_DIR}/.env"; set +a
fi

PORT="${HARBOR_HTTP_PORT:-18700}"

echo "── 校验 Harbor（镜像仓库）───────────────────────────────────────────────"

for i in $(seq 1 45); do
  BODY="$(curl -s "http://127.0.0.1:${PORT}/api/v2.0/health" 2>/dev/null || true)"
  if printf '%s' "${BODY}" | grep -q '"healthy"'; then
    echo "  [OK] /api/v2.0/health → healthy"
    break
  fi
  if [[ "${i}" -eq 45 ]]; then
    echo "  [FAIL] Harbor 3 分钟内未 healthy（响应: ${BODY:0:120}）" >&2
    echo "         排障: cd stacks/registry/harbor-installer && docker compose ps" >&2
    exit 1
  fi
  sleep 4
done

echo
echo "── 接入信息 ────────────────────────────────────────────────────────────"
echo "  入口       : http://${HARBOR_HOSTNAME:-<host>}:${PORT}"
echo "  管理员     : admin（口令见 .env 的 HARBOR_ADMIN_PASSWORD）"
echo "  Docker 客户端: 需将 http://${HARBOR_HOSTNAME:-<host>}:${PORT} 加入"
echo "               /etc/docker/daemon.json 的 insecure-registries（DEV 无 TLS）"
