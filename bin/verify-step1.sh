#!/usr/bin/env bash
# ==============================================================================
# bin/verify-step1.sh — 第一步·九项健康门禁（统一入口版）
# ==============================================================================
# 退出码: 0 = 无 FAIL；1 = 任一 FAIL。栈未部署 → warn 跳过（不计失败）。
#
# 三条门禁口径：
#   1) 业务门禁一律经统一入口（443 + 产品域名 + 平台 CA 真实校验，禁 -k）。
#      「直打 127.0.0.1:<宿主端口>」的旁路只作排障第二证据，不计入门禁。
#   2) 网关型门禁必须断言**响应身份**：入口路由里 Host(localhost)/Host(127.0.0.1)
#      是留给 Harbor 排障用的，所以只要响应带 Harbor 指纹（入口粘滞 cookie 或
#      server: nginx），这条门禁就不得算绿 —— 否则 ZITADEL/Casdoor/NATS 未部署时
#      会「借 Harbor 绿」；门禁域名与那条排障路由的 Host() 集合重叠时同样必然借绿。
#   3) 需要宿主二进制或外部归属信息的两枚门禁（①②）用双证据、且先核对归属：
#      ① PostgreSQL：裸 compose 档走容器内 pg_isready；HA 档（外部 PG 由容器托管、
#         宿主没有 pg 软件）走「本机 LB 口可连 + ${PG_CONTAINER_PREFIX}* 容器内
#         pg_isready 字面 accepting connections」—— 宿主侧判据在 HA 档必红且与 PG 好坏无关。
#      ② Redis：先核对 compose project 归属再连接 ⇒「容器在但属别的 project」与
#         「连不上」是两种不同的红，排障姿势也不同。
#      可选键（留空即内置默认）：PG_LB_PORT=5433 / PG_CONTAINER_PREFIX=pigsty-pg- /
#              REDIS_CONTAINER=opic-redis / REDIS_PROJECT=opic-ha-redis /
#              HARBOR_STICKY_COOKIE=opic_harbor_node / VERIFY_GATE_TIMEOUT=10。
#              PG_PORT 的 5432 语义保持不变（同一个键名被多处消费，改它等于改三处）。
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
TLS_ENTRY="${TRAEFIK_TLS:-false}"
CA_PEM="${CERT_CA_FILE:-${ROOT_DIR}/certs/ca.crt}"
BASE_DOM="${BASE_DOMAIN:-}"
HARBOR_DOM="${HARBOR_HOSTNAME:-registry.${BASE_DOM:-localhost}}"
HARBOR_PORT="${HARBOR_HTTP_PORT:-18700}"
GW_TIMEOUT="${VERIFY_GATE_TIMEOUT:-10}"
PG_LB_PORT="${PG_LB_PORT:-5433}"
PG_CONTAINER_PREFIX="${PG_CONTAINER_PREFIX:-pigsty-pg-}"
REDIS_CONTAINER="${REDIS_CONTAINER:-opic-redis}"
REDIS_PROJECT="${REDIS_PROJECT:-opic-ha-redis}"
HARBOR_STICKY_COOKIE="${HARBOR_STICKY_COOKIE:-opic_harbor_node}"
# 粘滞 cookie 名会进 grep -E 的模式位 ⇒ 只允许字母/数字/下划线/连字符（防把正则元字符写进模式）
[[ "${HARBOR_STICKY_COOKIE}" =~ ^[A-Za-z0-9_-]+$ ]] || { fail "HARBOR_STICKY_COOKIE 含非法字符：不能用于响应身份判定"; exit 1; }

HDR_TMP="$(mktemp)"; BODY_TMP="$(mktemp)"
cleanup() { rm -f "${HDR_TMP}" "${BODY_TMP}"; return 0; }   # trap 函数必须以 return 0 收尾，否则 EXIT 时把上一条的 rc 带出去
trap cleanup EXIT

PASS=0; FAILED=0; SKIPPED=0; GATE_WHY=""
gate() {  # gate <名称> <判定命令...>
  local name="$1"; shift
  GATE_WHY=""
  if "$@" >/dev/null 2>&1; then
    ok "${name}"
    PASS=$((PASS + 1))
  else
    fail "${name}${GATE_WHY:+ —— ${GATE_WHY}}"
    FAILED=$((FAILED + 1))
  fi
}
why() { GATE_WHY="$1"; }
running() { docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "${1}"; }

# ── 统一入口取回：TLS 档用真实域名（SNI + SAN + 平台 CA 链，无 -k），DEV 档走 web 口 ──
gw_get() {  # gw_get <域名> <路径>  → stdout=http_code；响应头进 HDR_TMP、响应体进 BODY_TMP
  local dom="$1" path="$2"
  : > "${HDR_TMP}"; : > "${BODY_TMP}"   # 每次清空，否则上一条门禁的 Harbor 指纹会串味
  if [[ "${TLS_ENTRY}" == "true" ]]; then
    [[ -f "${CA_PEM}" ]] || { why "缺平台 CA ${CA_PEM}（先跑 bin/gen-certs.sh）"; echo "000"; return 1; }
    curl -sS -D "${HDR_TMP}" -o "${BODY_TMP}" -w '%{http_code}' --max-time "${GW_TIMEOUT}" \
      --cacert "${CA_PEM}" --resolve "${dom}:${WSS_PORT}:127.0.0.1" \
      "https://${dom}:${WSS_PORT}${path}" 2>/dev/null
  else
    curl -sS -D "${HDR_TMP}" -o "${BODY_TMP}" -w '%{http_code}' --max-time "${GW_TIMEOUT}" \
      -H "Host: ${dom}" "http://127.0.0.1:${WEB_PORT}${path}" 2>/dev/null
  fi
}

# 响应身份：带任一 Harbor 指纹即认定「这条打到的是 Harbor，不是本门禁的目标服务」
served_by_harbor() { grep -qiE "${HARBOR_STICKY_COOKIE}|^server:[[:space:]]*nginx" "${HDR_TMP}"; }
code_in() { local c="$1"; shift; local w; for w in "$@"; do [[ "${c}" == "${w}" ]] && return 0; done; return 1; }

# 门禁域名不得与入口排障路由的 Host() 集合重叠（否则必然借 Harbor 绿）
dom_is_product() { [[ "${1}" == "${BASE_DOM}" || "${1}" == *".${BASE_DOM}" ]]; }

gate_pg() {
  # 档一：compose 裸 PG（stacks/database，minimal 档）——原判据
  if running opic-pg; then
    docker exec opic-pg pg_isready -U postgres -t 1 >/dev/null && return 0
    why "opic-pg 容器内 pg_isready 失败"; return 1
  fi
  # 档二：HA 档（外部 PG 由容器托管，宿主**没有**任何 pg 二进制 ⇒ 宿主判据必红且与 PG 好坏无关）
  # 两条独立证据（判据必须在本站有可行载体，且比的是 stdout 字面而非 rc）：
  #   ① 本机 LB 口可连（bash /dev/tcp，零宿主二进制依赖）
  #   ② ${pre}* 容器内 pg_isready 字面 accepting connections
  local lb="${PG_LB_PORT:-5433}" pre="${PG_CONTAINER_PREFIX:-pigsty-pg-}" c out
  if ! timeout 2 bash -c "exec 3<>/dev/tcp/127.0.0.1/${lb}" 2>/dev/null; then
    why "HA 档：本机 LB 口 :${lb} 不可连（haproxy 未起？）"; return 1
  fi
  c="$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E "^${pre}" | head -1)"
  [ -n "${c}" ] || { why "HA 档：LB :${lb} 可连，但无 ${pre}* 容器作第二证据"; return 1; }
  # 部分镜像里 docker exec C command -v X 会假报成功 ⇒ 一律走 bash -lc 取字面输出
  out="$(docker exec "${c}" bash -lc "pg_isready -h 127.0.0.1 -p ${lb} -t 2" 2>&1)"
  case "${out}" in
    *"accepting connections"*) return 0 ;;
    *) why "HA 档：LB :${lb} 可连但 ${c} 内 pg_isready 非 accepting connections（$(printf '%.60s' "${out}")）"; return 1 ;;
  esac
}
# 口令走 REDISCLI_AUTH 继承（不进 argv）：先导出，再让 docker exec 原样带上
gate_redis() {
  # 先**核对归属**再连接 ⇒ 「容器在但属别的 project」与「连不上」是两种可区分的红
  local cn="${REDIS_CONTAINER:-opic-redis}" pj="${REDIS_PROJECT:-opic-ha-redis}" own
  running "${cn}" || { why "容器 ${cn} 缺席（HA 档未起 或 stacks/redis 未装）"; return 1; }
  own="$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project" }}' "${cn}" 2>/dev/null)"
  if [ "${own}" != "${pj}" ]; then
    why "归属不符：${cn} 属 project=[${own:-空}]，期望 [${pj}]（先核对 stacks/redis 与 ha-stack 谁拥有它）"
    return 1
  fi
  local REDISCLI_AUTH="${REDIS_PASSWORD:-}"
  export REDISCLI_AUTH
  docker exec -e REDISCLI_AUTH "${cn}" redis-cli --no-auth-warning ping | grep -q PONG \
    || { why "PING 非 PONG（NOAUTH 或口令与 .env 漂移）"; return 1; }
}
gate_traefik() { curl -fsS --max-time "${GW_TIMEOUT}" "http://127.0.0.1:${WEB_PORT}/ping" >/dev/null; }

gate_zitadel() {
  dom_is_product "${ZITADEL_DOMAIN:-localhost}" || { why "ZITADEL_DOMAIN=${ZITADEL_DOMAIN:-localhost} 不是站点产品域名（会与入口排障路由撞车）"; return 1; }
  local c; c="$(gw_get "${ZITADEL_DOMAIN}" /debug/healthz)" || true
  served_by_harbor && { why "响应是 Harbor 不是 ZITADEL（借绿）"; return 1; }
  [[ "${c}" == "200" ]] || { why "healthz=${c}"; return 1; }
}
gate_zlogin() {
  dom_is_product "${ZITADEL_DOMAIN:-localhost}" || { why "ZITADEL_DOMAIN 不是站点产品域名"; return 1; }
  local c; c="$(gw_get "${ZITADEL_DOMAIN}" /ui/v2/login)" || true
  served_by_harbor && { why "响应是 Harbor 不是 ZITADEL（借绿）"; return 1; }
  code_in "${c}" 200 302 307 || { why "login=${c}"; return 1; }
}
gate_casdoor() {
  local c; c="$(gw_get "casdoor.${BASE_DOM}" /)" || true
  served_by_harbor && { why "响应是 Harbor 不是 Casdoor"; return 1; }
  code_in "${c}" 200 302 || { why "casdoor=${c}"; return 1; }
}
gate_nats() {
  local c; c="$(gw_get "nats.${BASE_DOM}" /jsz)" || true
  served_by_harbor && { why "响应是 Harbor 不是 NATS"; return 1; }
  [[ "${c}" == "200" ]] || { why "jsz=${c}"; return 1; }
  ! grep -q '"error"' "${BODY_TMP}"
}
gate_temporal(){ docker run --rm --network "${DOCKER_NETWORK:-opic-net}" \
                  --entrypoint temporal "${TEMPORAL_ADMINTOOLS_IMAGE:-temporalio/admin-tools}:${TEMPORAL_ADMINTOOLS_IMAGE_TAG:-1.30.4}" \
                  operator cluster health --address "temporal:${TEMPORAL_GRPC_PORT:-7233}" >/dev/null; }
gate_harbor() {
  local c; c="$(gw_get "${HARBOR_DOM}" /api/v2.0/health)" || true
  [[ "${c}" == "200" ]] || { why "经入口 health=${c}"; return 1; }
  served_by_harbor || { why "响应无 Harbor 入口指纹（未走统一入口的 LB？）"; return 1; }
  grep -q '"components"' "${BODY_TMP}" && grep -q '"status":"healthy"' "${BODY_TMP}"
}

echo "═══ 第一步·九项健康门禁（统一入口版）═════════════════════════════════════"
gate "① PostgreSQL   (opic-pg 或 HA 档 LB:${PG_LB_PORT:-5433})" gate_pg
gate "② Redis         (${REDIS_CONTAINER:-opic-redis} @project ${REDIS_PROJECT:-opic-ha-redis})" gate_redis
gate "③ Traefik       (web:${WEB_PORT} /ping)"  gate_traefik

if running opic-zitadel; then
  gate "④ ZITADEL API   (经入口 /debug/healthz)"  gate_zitadel
else
  warn "④ ZITADEL 未安装（跳过）"; SKIPPED=$((SKIPPED + 1))
fi
if running opic-zitadel-login; then
  gate "⑤ ZITADEL Login (经入口 /ui/v2/login)"    gate_zlogin
else
  warn "⑤ ZITADEL Login 未安装（跳过）"; SKIPPED=$((SKIPPED + 1))
fi
if running opic-casdoor; then
  gate "⑥ Casdoor       (经入口 casdoor.${BASE_DOM})" gate_casdoor
else
  warn "⑥ Casdoor 未安装（跳过）"; SKIPPED=$((SKIPPED + 1))
fi
if running opic-nats; then
  gate "⑦ NATS JetStream(经入口 nats.${BASE_DOM}/jsz)" gate_nats
else
  warn "⑦ NATS 未安装（跳过）"; SKIPPED=$((SKIPPED + 1))
fi
if running opic-temporal; then
  gate "⑧ Temporal      (grpc:${TEMPORAL_GRPC_PORT:-7233} 容器网内)" gate_temporal
else
  warn "⑧ Temporal 未安装（跳过）"; SKIPPED=$((SKIPPED + 1))
fi

if running harbor-core; then
  gate "⑨ Harbor        (经入口 ${HARBOR_DOM}:${WSS_PORT})" gate_harbor
  LOCAL_CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time "${GW_TIMEOUT}" \
                 "http://127.0.0.1:${HARBOR_PORT}/api/v2.0/health" 2>/dev/null || echo 000)"
  if [[ "${LOCAL_CODE}" == "200" ]]; then
    info "   └ 第二证据：本机明文 :${HARBOR_PORT} 亦 200（排障用，不计入门禁）"
  else
    warn "   └ 第二证据：本机明文 :${HARBOR_PORT} 返回 ${LOCAL_CODE}"
  fi
else
  warn "⑨ Harbor 未安装（跳过）"; SKIPPED=$((SKIPPED + 1))
fi

echo "═══════════════════════════════════════════════════════════════════════"
echo "  通过 ${PASS} / 跳过 ${SKIPPED} / 失败 ${FAILED}"
[[ "${FAILED}" -eq 0 ]] || { fail "存在未通过门禁 —— 排障提示见 docs/运维手册-step1.md"; exit 1; }
ok "第一步健康门禁无失败项（跳过的为未部署栈）"
