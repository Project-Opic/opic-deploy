#!/usr/bin/env bash
# ==============================================================================
# OPIC 离线介质包 · 打包脚本（在有网/源机器执行，如生产 192.168.3.200）
# 产出: opic-offline-kit-<ver>.tar.gz（镜像 tar + 介质包本体，目标机离线安装）
# 用法: bash pack.sh [版本号，默认 v3.2.0]
# ==============================================================================
set -euo pipefail

VER="${1:-v3.2.0}"
KIT_DIR="$(cd "$(dirname "$0")" && pwd)"
STAGE="$(mktemp -d)/kit"

echo "==> [1/4] 收集介质包本体（脚本/编排/配置/文档）"
mkdir -p "$STAGE"
cp -r "$KIT_DIR"/{docker-compose.demo.yml,docker-compose.demo-sso.yml,install.sh,README.md,configs} "$STAGE/"

echo "==> [2/4] 导出镜像（docker save，含 SSO 组件）"
IMAGES=(
  "traefik:v3.7.10"
  "postgres:16-alpine"
  "redis:8.10.2-alpine"
  "nats:2.14-alpine"
  "temporalio/auto-setup:1.29.0"
  "temporalio/ui:2.34.0"
  "casbin/casdoor:latest"
  "ghcr.io/zitadel/zitadel:v4.19.3"
  "ghcr.io/zitadel/zitadel-login:v4.19.3"
  "opic/techbase:latest"
  "opic/techbase-frontend:latest"
)
mkdir -p "$STAGE/images"
for img in "${IMAGES[@]}"; do
  docker image inspect "$img" > /dev/null 2>&1 || docker pull "$img"
  fn="images/$(echo "$img" | tr '/:' '__').tar"
  echo "  - $img"
  docker save "$img" -o "$STAGE/$fn"
done

echo "==> [3/4] techbase 应用镜像别名（生产 Harbor 名 → 通用名,保证与 compose 一致）"
docker tag "192.168.3.200:18700/opic/techbase:${VER}" "opic/techbase:latest" 2>/dev/null || true
docker tag "192.168.3.200:18700/opic/techbase-frontend:latest" "opic/techbase-frontend:latest" 2>/dev/null || true
docker save "opic/techbase:latest" -o "$STAGE/images/opic_techbase_latest.tar"
docker save "opic/techbase-frontend:latest" -o "$STAGE/images/opic_techbase-frontend_latest.tar"

echo "==> [4/4] 打包并生成校验和"
OUT="opic-offline-kit-${VER}.tar.gz"
tar -czf "$OUT" -C "$(dirname "$STAGE")" kit
sha256sum "$OUT" > "${OUT}.sha256"
echo
echo "✅ 介质包完成: $(pwd)/$OUT ($(du -h "$OUT" | cut -f1))"
echo "   校验和: $(cat "${OUT}.sha256")"
echo "   传输到目标机后: bash install.sh（见 README.md）"
