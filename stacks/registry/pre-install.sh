#!/usr/bin/env bash
# ==============================================================================
# pre-install: registry — 获取 Harbor 安装器、渲染配置、执行官方安装
# ==============================================================================
# Harbor 由官方安装器自管 compose（生成 harbor/ 项目与 harbor 网络），不走本仓
# 的 stacks compose 约定 —— 这是**刻意的例外**：安装器负责 prepare 配置渲染、
# 内部网络与生命周期，我们只负责参数来源（.env）与验收（post-install.sh）。
#
# 获取顺序: ① stacks/registry/harbor-installer 已存在则复用
#           ② HARBOR_INSTALLER_DIR 指向的已解压安装器（离线环境推荐，拷贝使用不动原目录）
#           ③ 在线下载 GitHub release（HARBOR_VERSION）
#           ④ 本地离线包 packages/harbor-online-installer-*.tgz
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

VERSION="${HARBOR_VERSION:-v2.15.2}"
PKG_DIR="${ROOT_DIR}/${HARBOR_PACKAGE_DIR:-packages}"
INSTALLER_DIR="${STACK_DIR}/harbor-installer"
TPL="${STACK_DIR}/harbor.yml.tpl"

echo "── Harbor 安装器准备（${VERSION}）────────────────────────────────────────"

if [[ ! -f "${INSTALLER_DIR}/install.sh" ]]; then
  mkdir -p "${PKG_DIR}" "${INSTALLER_DIR}"
  if [[ -n "${HARBOR_INSTALLER_DIR:-}" && -f "${HARBOR_INSTALLER_DIR}/install.sh" ]]; then
    echo "  复用已解压安装器（拷贝）: ${HARBOR_INSTALLER_DIR}"
    cp -a "${HARBOR_INSTALLER_DIR}/." "${INSTALLER_DIR}/"
  fi
  TGZ="${PKG_DIR}/harbor-online-installer-${VERSION}.tgz"
  if [[ ! -f "${TGZ}" ]]; then
    URL="https://github.com/goharbor/harbor/releases/download/${VERSION}/harbor-online-installer-${VERSION}.tgz"
    echo "  在线下载: ${URL}"
    if ! curl -fL --retry 2 -o "${TGZ}" "${URL}"; then
      echo "  [FAIL] 下载失败。离线方式：手工下载安装包放到 ${PKG_DIR}/ 后重跑" >&2
      exit 1
    fi
  else
    echo "  使用本地离线包: ${TGZ}"
  fi
  tar -xzf "${TGZ}" -C "${INSTALLER_DIR}" --strip-components=1
else
  echo "  复用已解压安装器: ${INSTALLER_DIR}"
fi

echo "── 渲染 harbor.yml ──────────────────────────────────────────────────────"

: "${HARBOR_HOSTNAME:?HARBOR_HOSTNAME 未配置}"
: "${HARBOR_HTTP_PORT:?HARBOR_HTTP_PORT 未配置}"
: "${HARBOR_ADMIN_PASSWORD:?HARBOR_ADMIN_PASSWORD 未配置}"
: "${HARBOR_DB_PASSWORD:?HARBOR_DB_PASSWORD 未配置}"
: "${HARBOR_DATA_DIR:?HARBOR_DATA_DIR 未配置}"

sed -e "s|__HARBOR_HOSTNAME__|${HARBOR_HOSTNAME}|g" \
    -e "s|__HARBOR_HTTP_PORT__|${HARBOR_HTTP_PORT}|g" \
    -e "s|__EXTERNAL_URL__|${HARBOR_HOSTNAME}:${HARBOR_HTTP_PORT}|g" \
    -e "s|__HARBOR_ADMIN_PASSWORD__|${HARBOR_ADMIN_PASSWORD}|g" \
    -e "s|__HARBOR_DB_PASSWORD__|${HARBOR_DB_PASSWORD}|g" \
    -e "s|__HARBOR_DATA_DIR__|${HARBOR_DATA_DIR}|g" \
    -e "s|__HARBOR_VERSION__|${VERSION#v}|g" \
    "${TPL}" > "${INSTALLER_DIR}/harbor.yml"
chmod 600 "${INSTALLER_DIR}/harbor.yml"
echo "  [OK] ${INSTALLER_DIR}/harbor.yml（已渲染，口令不回显）"

echo "── 执行官方安装（install.sh，自管 compose）───────────────────────────────"
mkdir -p "${HARBOR_DATA_DIR}"
cd "${INSTALLER_DIR}"
./install.sh

echo "  [OK] Harbor 安装完成（post-install.sh 负责健康验收）"
