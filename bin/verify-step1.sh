#!/usr/bin/env bash
# ==============================================================================
# bin/verify-step1.sh — 第一步·八项健康门禁（116 号 §四 F8；可独立重跑）
# ==============================================================================
# 退出码: 0 = 八项全绿；1 = 任一 FAIL。每项只验「运行时可用」，不重复各栈
# post-install 的深度校验。
# ==============================================================================
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=common.sh
source "${ROOT_DIR}/bin/common.sh"

load_env "${ROOT_DIR}" 2>/dev/null || true
[[ -f "${ROOT_DIR}/.env" ]] || { fail "未找到 .env"; exit 1; }
set -a; source "${ROOT_DIR}/.env"; set +a

WEB_PORT="${TRAEFIK_WEB_PORT:-80}"
WSS_PORT="${TRAEFIK_WEBSECURE_PORT:-443}"
# TLS 模式（生产档）：入口走 websecure(https, 自签证书用 -k)；DEV 默认 http
if [[ "${TRAEFIK_TLS:-false}" == "true" ]]; then
  SCHEME="https"; ENTRY_PORT="${WSS_PORT}"; CURLFLAGS="-kfsS"; CURLCODE="-ks -o /dev/null -w"
else
  SCHEME="http";  ENTRY_PORT="${WEB_PORT}";   CURLFLAGS="-fsS";  CURLCODE="-s -o /dev/null -w"
fi
DASH_PORT="${TRAEFIK_DASHBOARD_PORT:-8088}"
API_PORT="${ZITADEL_API_PORT:-18082}"
ZDOM="${ZITADEL_DOMAIN:-localhost}"
NATS_MON="${NATS_MONITOR_PORT:-8222}"
CAS_PORT="${CASDOOR_HTTP_PORT:-8000}"
HARBOR_PORT="${HARBOR_HTTP_PORT:-18700}"

PASS=0; FAILED=0
gate() {  # gate <名称> <判定命令...>
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    ok "${name}"
    PASS=$((PASS + 1))
  else
    fail "${name}"
    FAILED=$((FAILED + 1))
  fi
}

gate_pg()      { docker exec opic-pg pg_isready -U postgres -t 1 >/dev/null; }
gate_redis()   { docker exec opic-redis redis-cli --no-auth-warning -a "${REDIS_PASSWORD}" ping | grep -q PONG; }
gate_traefik() { curl -fsS "http://127.0.0.1:${WEB_PORT}/ping" >/dev/null; }  # /ping 返回 OK，只验状态码
gate_zitadel() { curl ${CURLFLAGS} -H "Host: ${ZDOM}" "${SCHEME}://127.0.0.1:${ENTRY_PORT}/debug/healthz"; }
gate_zlogin()  { local c; c="$(curl ${CURLCODE} '%{http_code}' -H "Host: ${ZDOM}" "${SCHEME}://127.0.0.1:${ENTRY_PORT}/ui/v2/login")"; [[ "${c}" == "200" || "${c}" == "302" || "${c}" == "307" ]]; }
gate_casdoor() { local c; c="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${CAS_PORT}/")"; [[ "${c}" == "200" || "${c}" == "302" ]]; }
gate_nats()    { curl -fsS "http://127.0.0.1:${NATS_MON}/jsz" | grep -vq '"error"'; }
gate_temporal(){ docker run --rm --network "${DOCKER_NETWORK:-opic-net}" \
                  --entrypoint temporal "${TEMPORAL_ADMINTOOLS_IMAGE:-temporalio/admin-tools}:${TEMPORAL_ADMINTOOLS_IMAGE_TAG:-1.30.4}" \
                  operator cluster health --address "temporal:${TEMPORAL_GRPC_PORT:-7233}" >/dev/null; }
gate_harbor()  { curl -fsS "http://127.0.0.1:${HARBOR_PORT}/api/v2.0/health" | grep -q healthy; }

echo "═══ 第一步·八项健康门禁 ═══════════════════════════════════════════════"
gate "① PostgreSQL   (opic-pg)"                 gate_pg
gate "② Redis         (opic-redis)"             gate_redis
gate "③ Traefik       (web:${WEB_PORT})"        gate_traefik
gate "④ ZITADEL API   (经网关 healthz, ${SCHEME})"     gate_zitadel
gate "⑤ ZITADEL Login (经网关 /ui/v2/login)"    gate_zlogin
gate "⑥ Casdoor       (port:${CAS_PORT})"       gate_casdoor
gate "⑦ NATS JetStream(port:${NATS_MON})"       gate_nats
gate "⑧ Temporal      (grpc:${TEMPORAL_GRPC_PORT:-7233})" gate_temporal
if docker ps --format '{{.Names}}' | grep -q '^harbor-core$'; then
  gate "⑨ Harbor      (port:${HARBOR_PORT})"    gate_harbor
else
  warn "⑨ Harbor 未安装（跳过）"
fi

echo "═══════════════════════════════════════════════════════════════════════"
echo "  通过 ${PASS} / 失败 ${FAILED}"
[[ "${FAILED}" -eq 0 ]] || { fail "存在未通过门禁 —— 排障提示见 docs/运维手册-step1.md"; exit 1; }
ok "八项健康门禁全绿 —— 第一步基础设施可用"
