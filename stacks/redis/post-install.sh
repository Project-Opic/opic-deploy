#!/usr/bin/env bash
# ==============================================================================
# post-install: redis — 校验鉴权与持久化
# ==============================================================================
set -euo pipefail

STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${STACK_DIR}/../.." && pwd)"

if [[ -f "${ROOT_DIR}/.env" ]]; then
  set -a; # shellcheck disable=SC1091
  source "${ROOT_DIR}/.env"; set +a
fi

# 口令走 REDISCLI_AUTH 环境变量继承，不进 argv（argv 里的值同机任何用户 ps 可见，也会进 shell history）
export REDISCLI_AUTH="${REDIS_PASSWORD:-}"

echo "── 校验 Redis ───────────────────────────────────────────────────────────"

for i in $(seq 1 30); do
  if docker exec -e REDISCLI_AUTH opic-redis redis-cli --no-auth-warning ping 2>/dev/null | grep -q PONG; then
    echo "  [OK] PING → PONG（鉴权生效）"
    break
  fi
  if [[ "${i}" -eq 30 ]]; then
    echo "  [FAIL] Redis 60 秒内未就绪，请查看：docker logs opic-redis" >&2
    exit 1
  fi
  sleep 2
done

AOF="$(docker exec -e REDISCLI_AUTH opic-redis redis-cli --no-auth-warning config get appendonly 2>/dev/null | tail -1)"
if [[ "${AOF}" == "yes" ]]; then
  echo "  [OK] AOF 持久化已启用"
else
  echo "  [WARN] AOF 未启用（appendonly=${AOF}）——缓存语义可能需要持久化"
fi

REDIS_PORT="${REDIS_PORT:-}"
echo
echo "── 接入信息 ────────────────────────────────────────────────────────────"
echo "  容器内地址 : redis://opic-redis:6379（应用面经 opic-net 访问）"
if [[ -n "${REDIS_PORT}" ]]; then
  echo "  宿主映射   : ${REDIS_PORT}（口令见 .env 的 REDIS_PASSWORD）"
fi
