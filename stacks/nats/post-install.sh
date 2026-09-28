#!/usr/bin/env bash
# ==============================================================================
# post-install: nats — 校验 JetStream 并输出接入信息
# ==============================================================================
# 校验方式刻意不依赖额外的 CLI 镜像：直接用 NATS 自带的 HTTP 监控端点 /jsz。
#   - JetStream 已启用 → /jsz 返回包含 config 的 JSON
#   - JetStream 未启用 → /jsz 返回 {"error":{"code":503,...}}
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

MONITOR_PORT="${NATS_MONITOR_PORT:-8222}"
CLIENT_PORT="${NATS_CLIENT_PORT:-4222}"
DATA_DIR="${NATS_DATA_DIR:-/opt/opic/nats/data}"

echo "── 校验 NATS / JetStream ────────────────────────────────────────────────"

# 等待容器健康
for i in $(seq 1 30); do
  if docker exec opic-nats wget --spider -q "http://127.0.0.1:8222/healthz" 2>/dev/null; then
    echo "  [OK] 容器健康检查通过"
    break
  fi
  if [[ "${i}" -eq 30 ]]; then
    echo "  [FAIL] 容器在 60 秒内未通过健康检查，请查看：docker logs opic-nats" >&2
    exit 1
  fi
  sleep 2
done

# 校验 JetStream（经监控端点）
JSZ="$(curl -fsS "http://127.0.0.1:${MONITOR_PORT}/jsz" 2>/dev/null || true)"
if [[ -z "${JSZ}" ]]; then
  echo "  [FAIL] 监控端点 http://127.0.0.1:${MONITOR_PORT}/jsz 无响应" >&2
  exit 1
fi

if ! printf '%s' "${JSZ}" | grep -q '"error"'; then
  STREAMS="$(printf '%s' "${JSZ}" | sed -n 's/.*"streams":\([0-9]*\).*/\1/p')"
  echo "  [OK] JetStream 已启用（现有 stream 数：${STREAMS:-0}）"
else
  echo "  [FAIL] JetStream 未启用，请检查 configs/nats/nats-server.conf 的 jetstream 段" >&2
  exit 1
fi

echo
echo "── 接入信息 ────────────────────────────────────────────────────────────"
echo "  客户端地址（容器内）: nats://opic-nats:4222"
echo "  客户端地址（宿主机）: nats://127.0.0.1:${CLIENT_PORT}"
echo "  监控端点            : http://127.0.0.1:${MONITOR_PORT}/varz"
echo "  JetStream 数据目录  : ${DATA_DIR}/jetstream"
echo
echo "  凭据: 见 .env 的 NATS_USER / NATS_PASSWORD（本脚本不回显口令）"
echo
echo "  提示: 事件主题（subject）与 stream 命名属 O-SYS 事件类型编目的范围，"
echo "        由建模期确定后再创建；本脚本刻意不预建任何 stream。"
