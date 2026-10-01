#!/usr/bin/env bash
# ==============================================================================
# post-install: zero-trust — 等待 ZITADEL 首启完成（建实例/建 schema）并验证路由
# ==============================================================================
# 首启（start-from-init）要建库表 schema + 初始化实例 + 生成 login 引导凭据，
# 冷启动可能超过 2 分钟（依赖镜像拉取与 PG 性能）。健康判定：
#   ① 容器 healthcheck（zitadel ready）
#   ② 经网关以正确 Host 访问 /debug/healthz（同时验证 traefik 路由）
#   ③ login 界面经网关可达
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

DOMAIN="${ZITADEL_DOMAIN:?ZITADEL_DOMAIN 未配置}"
API_PORT="${ZITADEL_API_PORT:-18082}"
WEB_PORT="${TRAEFIK_WEB_PORT:-80}"

echo "── 校验 ZITADEL（运维侧 IdP）────────────────────────────────────────────"

# ② 经网关验证 healthz（Host 头 = ZITADEL_DOMAIN，不依赖 DNS）
# 全新首启含建 schema（1~3 分钟），窗口给足 6 分钟
for i in $(seq 1 90); do
  CODE="$(curl -s -o /dev/null -w '%{http_code}' -H "Host: ${DOMAIN}" "http://127.0.0.1:${WEB_PORT}/debug/healthz" 2>/dev/null || true)"
  if [[ "${CODE}" == "200" ]]; then
    echo "  [OK] /debug/healthz → 200（经网关 ${WEB_PORT}，Host=${DOMAIN}）"
    break
  fi
  if [[ "${i}" -eq 90 ]]; then
    echo "  [FAIL] healthz 经网关 6 分钟内不可达（最后 code=${CODE}）。检查 opic-traefik 是否在跑、" >&2
    echo "         ZITADEL_DOMAIN 与 ZITADEL_EXTERNALPORT 是否一致、docker logs opic-zitadel" >&2
    exit 1
  fi
  sleep 4
done

# ③ 等待首启写入 login-client PAT（login UI 的 API 凭据，官方 v4 范式）
# api 容器无 shell，经一次性 alpine 查共享卷
for i in $(seq 1 30); do
  if docker run --rm -v "${DOCKER_NETWORK}-zitadel-bootstrap:/b" alpine       sh -c 'test -s /b/login-client.pat' >/dev/null 2>&1      || docker run --rm -v "zero-trust_zitadel-bootstrap:/b" alpine       sh -c 'test -s /b/login-client.pat' >/dev/null 2>&1; then
    echo "  [OK] login-client PAT 已写入"
    break
  fi
  if [[ "${i}" -eq 30 ]]; then
    echo "  [WARN] login-client PAT 未检出（以 login 探测为准）"
  fi
  sleep 2
done

# ④ login 界面（PAT 就绪后再探，给首启留 90 秒）
LOGIN_OK=""
for i in $(seq 1 45); do
  CODE="$(curl -s -o /dev/null -w '%{http_code}' -H "Host: ${DOMAIN}" "http://127.0.0.1:${WEB_PORT}/ui/v2/login" 2>/dev/null || true)"
  if [[ "${CODE}" == "200" || "${CODE}" == "307" || "${CODE}" == "302" ]]; then
    echo "  [OK] /ui/v2/login → ${CODE}（Login 服务经网关可达）"
    LOGIN_OK=1
    break
  fi
  sleep 2
done
if [[ -z "${LOGIN_OK}" ]]; then
  echo "  [FAIL] login 3 分钟内未就绪（最后 code=${CODE:-无}），请查看：docker logs opic-zitadel-login" >&2
  exit 1
fi

LOGIN_ADDR="http://${DOMAIN}:${ZITADEL_EXTERNALPORT:-80}"
echo
echo "── 接入信息 ────────────────────────────────────────────────────────────"
echo "  登录入口   : ${LOGIN_ADDR}"
echo "  管理员账号 : zitadel-admin@zitadel.localhost（口令见 .env 的 ZITADEL_ADMIN_PASSWORD）"
echo "  Console    : ${LOGIN_ADDR}/ui/console"
echo "  break-glass: curl -H 'Host: ${DOMAIN}' http://127.0.0.1:${API_PORT}/debug/healthz（API_PORT=${API_PORT} 含绑定地址）"
echo "  ⚠ masterkey: 丢失即无法解密既有数据 —— .env 必须纳入加密备份（见运维手册）"
