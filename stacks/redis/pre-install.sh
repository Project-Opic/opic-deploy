#!/usr/bin/env bash
# ==============================================================================
# pre-install: redis — 两条失败轴的提前拒绝闸门
# ==============================================================================
# 为什么放在 pre-install：bin/install-step1.sh 的 post-install 只在 up_stack 成功之后才
#   执行，闸门放 post-install 等于永远跑不到；pre-install 由 install-step1.sh 按文件存在性
#   调用（本栈此前没有这个文件 ⇒ 加上即生效，无需改 install-step1.sh）。
#
# 两条独立失败轴（都不需要真去 up 就能预判）：
#   轴①容器名撞车：本 compose 写死 container_name: opic-redis；若机器上已有一个同名但属
#       别的 compose project 的 Redis（例如外部/哨兵档），docker compose up 直接报名称冲突。
#   轴②宿主端口撞车：ports 默认 "${REDIS_PORT:-127.0.0.1:26379}:6379"，若该宿主口已被某个
#       host-network 进程（例如哨兵）占用 ⇒ 端口绑定失败。
#   （compose down 不连坐：project 隔离，故本闸门只拒绝、不代为清理。）
#
# 逃逸：确需起这个 minimal 档容器时，显式 OPIC_ALLOW_REDIS_STACK=1（值必须逐字为 1）。
# ==============================================================================
set -uo pipefail

STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${STACK_DIR}/../.." && pwd)"
[[ -f "${ROOT_DIR}/.env" ]] && { set -a; # shellcheck disable=SC1091
                                  source "${ROOT_DIR}/.env"; set +a; }

CN="${REDIS_CONTAINER:-opic-redis}"          # 本栈 compose 里写死的容器名
OWN="${REDIS_STACK_PROJECT:-redis}"          # up_stack 不带 -p ⇒ compose 默认 project = 目录名
ALLOW="${OPIC_ALLOW_REDIS_STACK:-0}"

reject() { echo "[FAIL] stacks/redis 拒绝部署：$*" >&2; echo "       确需继续: OPIC_ALLOW_REDIS_STACK=1 bash stacks/redis/pre-install.sh" >&2; exit 1; }

# 放行必须排在两条失败轴之前：若只在末尾 INFO 里提示 ALLOW，操作者照做了却仍然被拒，
#   等于闸门没有出口。
if [ "${ALLOW}" = "1" ]; then
  echo "  [WARN] OPIC_ALLOW_REDIS_STACK=1 ⇒ 闸门整体放行（两条失败轴都不再判）。" >&2
  echo "         若 up 仍失败，按本文件头部的轴①名称冲突 / 轴②宿主口占用逐条排障。" >&2
  exit 0
fi

# ── 轴①：同名容器的归属（只看 compose 标签，不按目录名或进程名猜）───────────────
if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "${CN}"; then
  proj="$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project" }}' "${CN}" 2>/dev/null)"
  cfgf="$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project.config_files" }}' "${CN}" 2>/dev/null)"
  st="$(docker inspect -f '{{ .State.Status }}' "${CN}" 2>/dev/null)"
  if [ "${proj}" != "${OWN}" ]; then
    reject "容器 ${CN} 已存在且属 project=[${proj:-空}]（配置文件 ${cfgf:-未知}，状态 ${st:-未知}），本栈 project=${OWN} ⇒ up 会名称冲突。外部 Redis 属数据面，本栈只是 minimal 档 fallback。"
  fi
  echo "  [ok] 轴①：${CN} 属本栈 project=${OWN}（状态 ${st:-未知}），允许 up"
else
  echo "  [ok] 轴①：无同名容器 ${CN}"
fi

# ── 轴②：宿主端口占用（REDIS_PORT 为空 ⇒ 回落 compose 默认 127.0.0.1:26379）─────
MAP="${REDIS_PORT:-127.0.0.1:26379}"
case "${MAP}" in
  *:*:*) HOSTP="$(printf '%s' "${MAP}" | cut -d: -f2); PORTP="$(printf '%s' "${MAP}" | cut -d: -f3)" ;;
  *:*)  HOSTP="$(printf '%s' "${MAP}" | cut -d: -f1); PORTP="$(printf '%s' "${MAP}" | cut -d: -f2)" ;;
  *)    HOSTP="127.0.0.1"; PORTP="${MAP}" ;;
esac
[ -n "${HOSTP}" ] || HOSTP="127.0.0.1"
if [ -n "${PORTP}" ] && ss -lntH "sport = :${PORTP}" 2>/dev/null | grep -q ":${PORTP}"; then
  # 归属取证走 /proc/<pid>/cgroup，不按进程名猜
  PIDS="$(ss -lntpH "sport = :${PORTP}" 2>/dev/null | grep -oE 'pid=[0-9]+' | cut -d= -f2 | sort -u | tr '\n' ' ')"
  for p in ${PIDS}; do
    cg="$(sed -n 's#.*name=##p' "/proc/${p}/cgroup" 2>/dev/null | head -1)"
    exe="$(readlink -f "/proc/${p}/exe" 2>/dev/null || echo NA)"
    reject "宿主 :${PORTP}（映射 ${MAP}）已被 pid=${p} 占用（exe=${exe} cgroup=${cg:-?}）⇒ 本栈 up 会绑定失败。请改 .env 的 REDIS_PORT 换一个宿主口（例如 127.0.0.1:26389）。"
  done
  reject "宿主 :${PORTP}（映射 ${MAP}）已被占用（未能取到 pid，请手工 ss -lntp 确认）"
fi
echo "  [ok] 轴②：宿主口 ${HOSTP}:${PORTP} 空闲"

# ── 口径提示（不拒绝）：使用外部 Redis 时消费方走的是外部实例 ⇒ 本栈即使起来也不计入门禁 ──
if [ -n "${EXT_REDIS_HOSTS:-}" ]; then
  echo "  [INFO] .env 已声明 EXT_REDIS_HOSTS（外部 Redis）⇒ 统一门禁只认 project=${REDIS_PROJECT:-opic-ha-redis}，本栈容器不计入。" >&2
fi
echo "  [OK] stacks/redis pre-install 闸门通过"
