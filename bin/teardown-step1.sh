#!/usr/bin/env bash
# ==============================================================================
# bin/teardown-step1.sh — 第一步·停止/回滚（严格逆序，115 号 §6.3 启停纪律）
# ==============================================================================
# 纪律:
#   - 回滚优先 down 而非 down -v：数据目录为 bind mount，down 不删数据
#   - Harbor 由安装器自管 compose，在其目录内单独 down
#   - --purge 连数据目录一并删除（**破坏性**，需确认）——仅 DEV 重置用
#
# 用法:
#   bash bin/teardown-step1.sh            # 逆序停止全部（保留数据）
#   bash bin/teardown-step1.sh --purge    # 停止并删除数据目录（需确认）
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=common.sh
source "${ROOT_DIR}/bin/common.sh"

PURGE=0
[[ "${1:-}" == "--purge" ]] && PURGE=1

load_env "${ROOT_DIR}" 2>/dev/null || true
[[ -f "${ROOT_DIR}/.env" ]] && { set -a; source "${ROOT_DIR}/.env"; set +a; }

NET="${DOCKER_NETWORK:-opic-net}"

# Harbor 先停（它晚装，逆序里最先停）
if docker ps -a --format '{{.Names}}' | grep -q '^harbor-core$'; then
  echo "── 停止 Harbor（安装器自管 compose）─────────────────────────────────────"
  (cd "${ROOT_DIR}/stacks/registry/harbor-installer" && docker compose down) \
    || warn "Harbor down 失败（可能已停止）"
fi

# 栈逆序（与 install-step1.sh 的 STACKS 相反）
REVERSED=(temporal nats casdoor zero-trust traefik redis database)
for s in "${REVERSED[@]}"; do
  if [[ -f "${ROOT_DIR}/stacks/${s}/docker-compose.yml" ]]; then
    echo "── 停止 ${s} ────────────────────────────────────────────────────────────"
    (cd "${ROOT_DIR}/stacks/${s}" && docker compose down) || warn "${s} down 失败（可能已停止）"
  fi
done

if [[ "${PURGE}" -eq 1 ]]; then
  echo
  warn "--purge 将删除以下数据目录（不可恢复）："
  for d in "${DATABASE_PG_DATA_DIR:-}" "${REDIS_DATA_DIR:-}" "${HARBOR_DATA_DIR:-}" "${NATS_DATA_DIR:-}" "${TEMPORAL_PG_DATA_DIR:-}"; do
    [[ -n "${d}" ]] && echo "    ${d}"
  done
  read -r -p "输入 PURGE 确认删除: " ans
  if [[ "${ans}" == "PURGE" ]]; then
    for d in "${DATABASE_PG_DATA_DIR:-}" "${REDIS_DATA_DIR:-}" "${HARBOR_DATA_DIR:-}" "${NATS_DATA_DIR:-}" "${TEMPORAL_PG_DATA_DIR:-}"; do
      [[ -n "${d}" && -d "${d}" ]] && rm -rf "${d}" && warn "已删除 ${d}"
    done
    docker network rm "${NET}" >/dev/null 2>&1 && info "已删除网络 ${NET}" || true
    ok "环境已重置（.env 保留；彻底重置请再执行 bin/gen-env.sh --force）"
  else
    warn "未确认，跳过数据删除"
  fi
else
  info "已按逆序停止（数据保留）。重装: bash bin/install-step1.sh"
fi
