#!/usr/bin/env bash
# ==============================================================================
# bin/gen-certs.sh — 生成入口 TLS 证书与动态配置（F2 前置；幂等）
# ==============================================================================
# ① 生成/复用自签 CA + 通配符证书（*.<BASE_DOMAIN>），供 Traefik websecure 使用。
#    生产替换为企业/O-CRT 证书：覆盖 certs/fullchain.pem、key.pem 后重启 traefik。
# ② 维护 dynamic/ 配置：TLS 证书声明 + http→https 全局重定向（仅 TRAEFIK_TLS=true）。
#    两项相互独立：证书已存在时仍会刷新重定向配置。
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=common.sh
source "${ROOT_DIR}/bin/common.sh"

load_env "${ROOT_DIR}" 2>/dev/null || true
[[ -f "${ROOT_DIR}/.env" ]] && { set -a; source "${ROOT_DIR}/.env"; set +a; }

DOMAIN="${BASE_DOMAIN:-localhost}"
CERT_DIR="${ROOT_DIR}/certs"
DYNAMIC_DIR="${ROOT_DIR}/configs/traefik/dynamic"
mkdir -p "${CERT_DIR}" "${DYNAMIC_DIR}"
chmod 700 "${CERT_DIR}"

# ── ① 动态配置：http→https 全局重定向（仅 TLS 模式；http 模式自动移除避免断链）──
if [[ "${TRAEFIK_TLS:-false}" == "true" ]]; then
  cat > "${DYNAMIC_DIR}/redirect.yml" <<'EOF'
http:
  routers:
    redirect-http-https:
      entryPoints: [web]
      rule: "PathPrefix(`/`)"
      priority: 1
      middlewares: [https-redirect]
      service: noop@internal
  middlewares:
    https-redirect:
      redirectScheme:
        scheme: https
        permanent: true
EOF
  ok "http→https 全局重定向已启用（dynamic/redirect.yml）"
else
  rm -f "${DYNAMIC_DIR}/redirect.yml"
  info "http 模式：无重定向配置"
fi

# ── ② 证书：已存在则复用，缺失则生成自签 CA + 通配符 ──────────────────────────
if [[ -s "${CERT_DIR}/ca.key" && -s "${CERT_DIR}/fullchain.pem" && -s "${CERT_DIR}/key.pem" ]]; then
  ok "证书已存在（${CERT_DIR}）—— 替换企业证书请覆盖 fullchain.pem/key.pem 后重启 traefik"
  exit 0
fi

info "生成自签 CA + 通配符证书（*.${DOMAIN}）……"

# 自签 CA（10 年）
openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
  -keyout "${CERT_DIR}/ca.key" -out "${CERT_DIR}/ca.crt" \
  -subj "/CN=OPIC Root CA" >/dev/null 2>&1

# 服务端私钥 + CSR（SAN：通配符 + 裸域 + 本机回环）
openssl req -newkey rsa:2048 -sha256 -nodes \
  -keyout "${CERT_DIR}/key.pem" -out "${CERT_DIR}/server.csr" \
  -subj "/CN=*.${DOMAIN}" >/dev/null 2>&1

cat > "${CERT_DIR}/san.cnf" <<EOF
subjectAltName=DNS:*.${DOMAIN},DNS:${DOMAIN},DNS:localhost,IP:127.0.0.1
extendedKeyUsage=serverAuth
EOF

openssl x509 -req -in "${CERT_DIR}/server.csr" \
  -CA "${CERT_DIR}/ca.crt" -CAkey "${CERT_DIR}/ca.key" -CAcreateserial \
  -out "${CERT_DIR}/fullchain.pem" -days 825 -sha256 \
  -extfile "${CERT_DIR}/san.cnf" >/dev/null 2>&1

# 动态 TLS 配置（指向证书文件）
cat > "${DYNAMIC_DIR}/tls.yml" <<EOF
tls:
  certificates:
    - certFile: /etc/traefik/certs/fullchain.pem
      keyFile: /etc/traefik/certs/key.pem
EOF

rm -f "${CERT_DIR}/server.csr" "${CERT_DIR}/san.cnf" "${CERT_DIR}/ca.srl"
chmod 600 "${CERT_DIR}/ca.key" "${CERT_DIR}/key.pem"
ok "证书就绪：${CERT_DIR}/ca.crt（分发给访问方导入信任），fullchain.pem/key.pem"
