#!/usr/bin/env bash
# ==============================================================================
# bin/gen-env.sh — 从 .env.example 生成 .env，自动填充全部口令（F1 凭据与密钥）
# ==============================================================================
# 纪律（115 号 S1）:
#   - 必须在任何 compose 之前完成 —— 密钥确定后再装，避免先起的容器拿旧口令
#   - 幂等优先：.env 已存在则拒绝覆盖（--force 才重建，重建前提示备份）
#   - ZITADEL_MASTERKEY 恰好 32 字符 —— 丢失即无法解密 ZITADEL 既有数据
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXAMPLE="${ROOT_DIR}/.env.example"
TARGET="${ROOT_DIR}/.env"

[[ -f "${EXAMPLE}" ]] || { echo "[FAIL] 缺少 ${EXAMPLE}" >&2; exit 1; }

if [[ -f "${TARGET}" && "${1:-}" != "--force" ]]; then
  echo "[SKIP] ${TARGET} 已存在（保持现有口令；确需重建: bash bin/gen-env.sh --force，先备份！）"
  exit 0
fi

if [[ -f "${TARGET}" && "${1:-}" == "--force" ]]; then
  echo "[WARN] 即将覆盖现有 ${TARGET} —— 旧口令随重建失效，已有数据将无法解密/连接"
  read -r -p "确认重建？输入 yes 继续: " ans
  [[ "${ans}" == "yes" ]] || { echo "已取消"; exit 1; }
fi

# 口令类变量：空值时填充复杂度合规口令（大写+小写+数字+符号，满足 ZITADEL/Harbor
# 默认口令策略）；masterkey 单独用恰好 32 字符 hex（AES 密钥，不做人机口令）
FILL_KEYS=(
  PG_ADMIN_PASSWORD REDIS_PASSWORD
  NATS_PASSWORD TEMPORAL_PG_PASSWORD
  ZITADEL_MASTERKEY ZITADEL_DB_PASSWORD ZITADEL_ADMIN_PASSWORD
  LOGIN_SESSION_COOKIE_SECRET
  CASDOOR_DB_PASSWORD HARBOR_ADMIN_PASSWORD HARBOR_DB_PASSWORD
)

[[ "$(id -u)" -eq 0 ]] || need_openssl=1
command -v openssl >/dev/null 2>&1 || { echo "[FAIL] 缺少 openssl" >&2; exit 1; }

TMP="$(mktemp)"
cp "${EXAMPLE}" "${TMP}"
for key in "${FILL_KEYS[@]}"; do
  if [[ "${key}" == "ZITADEL_MASTERKEY" ]]; then
    val="$(openssl rand -hex 16)"
  else
    # Op1- 前缀保证大写/小写/数字/符号齐备，剩余 24 位 hex 提供熵
    val="Op1-$(openssl rand -hex 12)"
  fi
  # 只替换该 key 的「空值」行（模板中口令均为空）
  python3 - "$TMP" "$key" "$val" <<'PY'
import re, sys
path, key, val = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(path).read()
src, n = re.subn(rf'(?m)^{key}=$', f'{key}={val}', src)
if n == 0:
    sys.exit(f'[FAIL] 模板中找不到空值行: {key}=')
open(path, 'w').write(src)
PY
  echo "  [OK] ${key} 已生成"
done

chmod 600 "${TMP}"
mv "${TMP}" "${TARGET}"
echo
echo "[OK] 已生成 ${TARGET}（权限 600）—— 口令只存在于该文件，请纳入加密备份（见运维手册）"
echo "     DEV 环境请按 docs/第一步-容器化部署.md 的端口表调整 *_PORT 与 ZITADEL_DOMAIN"
