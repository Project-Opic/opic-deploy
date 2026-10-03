#!/usr/bin/env bash
# ==============================================================================
# OPIC 离线介质包 · 一键部署（目标机执行；Linux x86_64 + Docker）
# 用法:
#   bash install.sh                 # core 档(本地登录,推荐 DEMO)
#   bash install.sh --with-sso      # 附带 Casdoor/ZITADEL(镜像含于介质包)
#   bash install.sh --check-only    # 仅前置检查
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")"

WITH_SSO=false
[[ "${1:-}" == "--with-sso" ]] && WITH_SSO=true
[[ "${1:-}" == "--check-only" ]] && CHECK_ONLY=true

echo "=============================================="
echo " OPIC 离线安装 · $(date '+%F %T')"
echo "=============================================="

# ── 1) 前置检查 ──
echo "==> [1/5] 前置检查"
command -v docker >/dev/null || { echo "✗ 未安装 docker"; exit 1; }
docker info > /dev/null 2>&1 || { echo "✗ docker 不可用(权限/daemon)"; exit 1; }
df -h . | awk 'NR==2 {print "  磁盘可用: " $4}'
FREE_GB=$(df -BG . | awk 'NR==2 {print substr($4,1,length($4)-1)}')
(( FREE_GB >= 20 )) || { echo "✗ 磁盘可用不足 20GB"; exit 1; }

# 端口占用检查(core)
for p in 28081 35432 36379 34222 37233 38088; do
  if ss -tln 2>/dev/null | grep -q ":$p "; then echo "✗ 端口 $p 已被占用（可在 .env 调整）"; exit 1; fi
done
echo "  docker / 磁盘 / 端口 OK"
[[ -n "${CHECK_ONLY:-}" ]] && { echo "== 仅检查模式，结束 =="; exit 0; }

# ── 2) 导入镜像 ──
echo "==> [2/5] 导入镜像(docker load)"
if ls images/*.tar > /dev/null 2>&1; then
  for f in images/*.tar; do
    docker load -q -i "$f" && echo "  - $f"
  done
else
  echo "  ⚠ 未找到 images/*.tar——若目标机可联网将自动 pull（离线环境请先拷贝 images/）"
fi

# ── 3) 生成配置(.env + 数据库初始化 SQL,口令随机) ──
echo "==> [3/5] 生成配置与口令"
if [[ -f .env ]]; then
  echo "  .env 已存在,保留既有口令"
else
  RAND() { openssl rand -hex "${1:-12}"; }
  cat > .env << EOF
# OPIC DEMO 自动生成 $(date '+%F %T') —— 口令请妥善保管
PG_ROOT_PASSWORD=$(RAND 16)
OPIC_DB_PASSWORD=$(RAND 16)
CASDOOR_DB_PASSWORD=$(RAND 16)
ZITADEL_DB_PASSWORD=$(RAND 16)
TEMPORAL_PASSWORD=$(RAND 16)
REDIS_PASSWORD=$(RAND 16)
ZITADEL_MASTERKEY=$(RAND 16)$(RAND 16)
ZITADEL_ADMIN_PASSWORD=Op1-$(RAND 8)
ZITADEL_HOST_IP=$(hostname -I | awk '{print $1}')
EOF
  echo "  ⚠ 口令已写入 .env(随机生成),请备份该文件"
fi

# 数据库初始化 SQL(镜像 postgres 官方 initdb 机制,首启自动执行)
mkdir -p runtime/initdb
cat > runtime/initdb/01-init.sql << EOF
-- 由 install.sh 生成:多库 + 独立账号
CREATE ROLE opic LOGIN PASSWORD '${OPIC_DB_PASSWORD:-$(grep OPIC_DB_PASSWORD .env | cut -d= -f2)}';
CREATE DATABASE opicdb OWNER opic;
\c opicdb
CREATE SCHEMA otechbase AUTHORIZATION opic;
\c postgres
CREATE ROLE casdoor LOGIN PASSWORD '$(grep CASDOOR_DB_PASSWORD .env | cut -d= -f2)';
CREATE DATABASE casdoor OWNER casdoor;
CREATE ROLE temporal LOGIN PASSWORD '$(grep TEMPORAL_PASSWORD .env | cut -d= -f2)' CREATEDB;
CREATE DATABASE temporal OWNER temporal;
CREATE DATABASE temporal_visibility OWNER temporal;
CREATE ROLE zitadel LOGIN PASSWORD '$(grep ZITADEL_DB_PASSWORD .env | cut -d= -f2)';
CREATE DATABASE zitadel OWNER zitadel;
EOF

# ── 4) 拉起栈 ──
echo "==> [4/5] 拉起服务"
COMPOSE=(docker compose -p opic-demo -f docker-compose.demo.yml)
$WITH_SSO && COMPOSE+=(-f docker-compose.demo-sso.yml)
"${COMPOSE[@]}" up -d

echo "==> [5/5] 等待健康(最长 120s)"
for i in $(seq 1 24); do
  ST=$(docker inspect -f '{{.State.Health.Status}}' opic-demo-pg 2>/dev/null || echo starting)
  [[ "$ST" == "healthy" ]] && break
  sleep 5
done
sleep 10   # techbase goose 迁移 + 种子
FRONT_PORT=$(grep -E "^FRONTEND_PORT=" .env | cut -d= -f2 || echo 28081)
HOST_IP=$(hostname -I | awk '{print $1}')

echo
echo "=============================================="
echo " ✅ OPIC DEMO 部署完成"
echo "=============================================="
echo " 访问入口:   http://${HOST_IP}:${FRONT_PORT:-28081}"
echo " 默认账号:   admin / admin123（本地登录入口,带图形验证码）"
echo " 演示功能:   客户申请 → 流程审批 → 流程设计 → AI 助理 → 日志审计 → 隔离信息"
echo " Temporal UI: http://${HOST_IP}:38088"
$WITH_SSO && {
  echo " Casdoor:    http://${HOST_IP}:28001（admin/123,首次登录请改密）"
  echo " ZITADEL:    http://${HOST_IP}:28080（zitadel-admin@zitadel.localhost,口令见 .env）"
}
echo " 常用命令:   docker compose -p opic-demo -f docker-compose.demo.yml ps|logs|down"
echo "=============================================="
