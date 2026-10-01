#!/usr/bin/env bash
# ==============================================================================
# bin/common.sh — opic-deploy 编排脚本公共函数（被 install/verify/teardown 引用）
# ==============================================================================

# ── 输出 ─────────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  C_G=$'\033[32m'; C_R=$'\033[31m'; C_Y=$'\033[33m'; C_B=$'\033[36m'; C_0=$'\033[0m'
else
  C_G=""; C_R=""; C_Y=""; C_B=""; C_0=""
fi

info()  { printf '%s[INFO]%s %s\n'  "${C_B}" "${C_0}" "$*"; }
ok()    { printf '%s[ OK ]%s %s\n'  "${C_G}" "${C_0}" "$*"; }
warn()  { printf '%s[WARN]%s %s\n'  "${C_Y}" "${C_0}" "$*"; }
fail()  { printf '%s[FAIL]%s %s\n'  "${C_R}" "${C_0}" "$*" >&2; }

die()   { fail "$*"; exit 1; }

# ── 环境 ─────────────────────────────────────────────────────────────────────
# 装载 .env（口令与端口唯一来源）；缺失时报错并指向 gen-env.sh
load_env() {
  local root="$1"
  [[ -f "${root}/.env" ]] || die "未找到 ${root}/.env —— 先执行: bash bin/gen-env.sh"
  set -a; # shellcheck disable=SC1091
  source "${root}/.env"; set +a
}

# ── 前置检查 ─────────────────────────────────────────────────────────────────
need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1（请先安装）"
}

# 端口是否空闲（空闲返回 0）；PORT 形如 "18880" 或 "127.0.0.1:18082"
port_free() {
  local p="$1" hostport
  hostport="${p##*:}"
  ! (command -v ss >/dev/null 2>&1 && ss -tln | awk '{print $4}' | grep -qE ":${hostport}$")
}

# ── HTTP 等待 ────────────────────────────────────────────────────────────────
# 等待 URL 返回期望状态码；用法: wait_http <url> [期望码,默认200] [次数,默认30]
# 支持自定义 Host 头: HDR_HOST 变量非空时附加
wait_http() {
  local url="$1" want="${2:-200}" tries="${3:-30}" code i
  for i in $(seq 1 "${tries}"); do
    if [[ -n "${HDR_HOST:-}" ]]; then
      code="$(curl -s -o /dev/null -w '%{http_code}' -H "Host: ${HDR_HOST}" "${url}" 2>/dev/null || true)"
    else
      code="$(curl -s -o /dev/null -w '%{http_code}' "${url}" 2>/dev/null || true)"
    fi
    [[ "${code}" == "${want}" ]] && return 0
    sleep 2
  done
  return 1
}

# ── compose 封装 ─────────────────────────────────────────────────────────────
# up_stack <name>: 在 stacks/<name> 起 compose（不带 --wait —— 有栈刻意不设
# healthcheck（如 zitadel，见栈头注释），就绪判定统一由 post-install 门禁承担）
up_stack() {
  local name="$1" dir
  dir="${ROOT_DIR}/stacks/${name}"
  [[ -f "${dir}/docker-compose.yml" ]] || die "stack ${name} 不存在 compose 文件"
  (cd "${dir}" && docker compose up -d) || die "stack ${name} 启动失败"
}
