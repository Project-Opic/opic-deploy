#!/usr/bin/env bash
# ==============================================================================
# post-install: temporal — 等待服务就绪、创建业务命名空间、输出接入信息
# ==============================================================================
# 健康检查用官方口径 temporal operator cluster health（端口 7233 是 gRPC，
# 不能用 curl 探测）。CLI 经 admin-tools 镜像一次性执行，不留常驻容器。
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

NET="${DOCKER_NETWORK:-opic-net}"
NS="${TEMPORAL_NAMESPACE:-opic}"
RETENTION="${TEMPORAL_RETENTION_DAYS:-30}"
UI_PORT="${TEMPORAL_UI_PORT:-8233}"
GRPC_PORT="${TEMPORAL_GRPC_PORT:-7233}"
TOOLS_IMAGE="${TEMPORAL_ADMINTOOLS_IMAGE:-temporalio/admin-tools}:${TEMPORAL_ADMINTOOLS_IMAGE_TAG:-1.30.4}"

# 统一注入 server 地址（容器网 DNS 名），避免 CLI 回落 localhost:7233
temporal_cli() {
  docker run --rm --network "${NET}" --entrypoint temporal "${TOOLS_IMAGE}" "$@"
}
ADDR="--address temporal:${GRPC_PORT}"

echo "── 校验 Temporal Server ────────────────────────────────────────────────"

# 等待 frontend 就绪（首启要建 schema，通常 30~60 秒）
HEALTH=""
for i in $(seq 1 45); do
  HEALTH="$(temporal_cli operator cluster health ${ADDR} 2>/dev/null | tr -d '\r' || true)"
  if printf '%s' "${HEALTH}" | grep -q "SERVING"; then
    echo "  [OK] cluster health = SERVING"
    break
  fi
  if [[ "${i}" -eq 45 ]]; then
    echo "  [FAIL] 90 秒内未就绪，请查看：docker logs opic-temporal" >&2
    exit 1
  fi
  sleep 2
done

# 业务命名空间（幂等：已存在则跳过）
echo "── 业务命名空间 ────────────────────────────────────────────────────────"
if temporal_cli operator namespace describe ${ADDR} --namespace "${NS}" >/dev/null 2>&1; then
  echo "  [SKIP] 命名空间 ${NS} 已存在"
else
  temporal_cli operator namespace create ${ADDR} --namespace "${NS}" --retention "${RETENTION}d"
  echo "  [OK] 已创建命名空间 ${NS}（retention ${RETENTION} 天）"
fi

echo
echo "── 接入信息 ────────────────────────────────────────────────────────────"
echo "  gRPC frontend（容器内）: opic-temporal:7233"
echo "  gRPC frontend（宿主机）: 127.0.0.1:${GRPC_PORT}"
echo "  Web UI                 : http://127.0.0.1:${UI_PORT}"
echo "  业务命名空间            : ${NS}"
echo "  持久化                  : 见 .env 的 TEMPORAL_PG_DATA_DIR（PostgreSQL 16）"
echo
echo "  ⚠️  安全提醒：Temporal 的 gRPC frontend 与 Web UI 默认不启用认证。"
echo "      本 stack 仅面向内网；对外暴露前须做访问控制（反向代理 + 鉴权 / mTLS）。"
echo "      详见 README「安全须知」。"
