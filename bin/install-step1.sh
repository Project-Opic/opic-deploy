#!/usr/bin/env bash
# ==============================================================================
# bin/install-step1.sh — 第一步·基础设施安装编排（容器化模式，F0~F8）
# ==============================================================================
# 对应 116 号 §四 的执行序；停止/回滚用 bin/teardown-step1.sh（严格逆序）。
#
# 用法:
#   bash bin/install-step1.sh                 # 全量安装（F0~F8）
#   bash bin/install-step1.sh registry        # 只装/重装指定 stack（绕过 F0~F1 前置）
#   bash bin/install-step1.sh --no-registry   # 全量但跳过 Harbor（离线拿不到安装包时）
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=common.sh
source "${ROOT_DIR}/bin/common.sh"

ONLY="${1:-}"
NO_REGISTRY=0
[[ "${ONLY}" == "--no-registry" ]] && { ONLY=""; NO_REGISTRY=1; }

# ── F0 主机与运行时前置 ──────────────────────────────────────────────────────
echo "═══ F0 主机与运行时前置 ═══════════════════════════════════════════════"
need_cmd docker
need_cmd curl
need_cmd openssl
docker compose version >/dev/null 2>&1 || die "Docker Compose v2 不可用"
info "Docker: $(docker --version) / $(docker compose version --short)"

# opic-net 必须先于任何 compose up（compose 引用 external 网络）
NET="${DOCKER_NETWORK:-opic-net}"
docker network inspect "${NET}" >/dev/null 2>&1 \
  || docker network create "${NET}" >/dev/null
ok "容器网络 ${NET} 就绪"

# 磁盘护栏（镜像 + 数据 ≥ 20 GiB）
AVAIL_KB="$(df -Pk /opt | awk 'NR==2 {print $4}')"
if [[ "${AVAIL_KB}" -lt $((20 * 1024 * 1024)) ]]; then
  warn "根分区可用空间不足 20 GiB（当前 $((AVAIL_KB / 1024 / 1024)) GiB）——Harbor 与镜像层可能吃紧"
fi

# ── F1 凭据与密钥 ────────────────────────────────────────────────────────────
echo "═══ F1 凭据与密钥 ═════════════════════════════════════════════════════"
if [[ -z "${ONLY}" ]]; then
  bash "${ROOT_DIR}/bin/gen-env.sh"
fi
load_env "${ROOT_DIR}"
ok ".env 已装载（口令不回显）"

# ── 栈集合与执行序（116 号 §二；registry 特例由安装器自管）───────────────────
STACKS=(database redis traefik zero-trust casdoor nats temporal)
if [[ "${NO_REGISTRY}" -eq 0 ]]; then
  REGISTRY=1
fi

if [[ -n "${ONLY}" ]]; then
  case "${ONLY}" in
    registry) STACKS=(); REGISTRY=1 ;;
    *) STACKS=("${ONLY}"); REGISTRY=0 ;;
  esac
fi

# ── F2 数据目录 ──────────────────────────────────────────────────────────────
echo "═══ F2 数据目录 ═══════════════════════════════════════════════════════"
for d in "${DATABASE_PG_DATA_DIR:-}" "${REDIS_DATA_DIR:-}" "${HARBOR_DATA_DIR:-}"; do
  [[ -n "${d}" ]] || continue
  mkdir -p "${d}"
  ok "数据目录 ${d}"
done

# ── F3~F7 逐栈部署（启动正序；每栈过 post-install 门禁才进下一栈）────────────
for s in "${STACKS[@]}"; do
  echo "═══ stack: ${s} ══════════════════════════════════════════════════════"
  if [[ -f "${ROOT_DIR}/stacks/${s}/pre-install.sh" ]]; then
    bash "${ROOT_DIR}/stacks/${s}/pre-install.sh"
  fi
  up_stack "${s}"
  if [[ -f "${ROOT_DIR}/stacks/${s}/post-install.sh" ]]; then
    bash "${ROOT_DIR}/stacks/${s}/post-install.sh"
  fi
  ok "stack ${s} 完成"
done

if [[ "${REGISTRY:-0}" -eq 1 ]]; then
  echo "═══ stack: registry（Harbor，安装器自管）═══════════════════════════════"
  bash "${ROOT_DIR}/stacks/registry/pre-install.sh"
  bash "${ROOT_DIR}/stacks/registry/post-install.sh"
  ok "stack registry 完成"
fi

# ── F8 验证收口 ──────────────────────────────────────────────────────────────
echo "═══ F8 验证收口 ═══════════════════════════════════════════════════════"
bash "${ROOT_DIR}/bin/verify-step1.sh"
