#!/usr/bin/env bash
# ==============================================================================
# bin/backup-prod.sh — 生产档自动备份（PG 全库 + Harbor 数据 + 配置）
# ==============================================================================
# 策略（118 号 §五）：每日凌晨全量，保留 N 天（默认 14）；Harbor 数据周度冷备（周日）。
# 建议 crontab：0 2 * * * /opt/opic-prod/bin/backup-prod.sh >> /opt/opic-backup/backup.log 2>&1
# ==============================================================================
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=common.sh
source "${ROOT_DIR}/bin/common.sh"

load_env "${ROOT_DIR}" 2>/dev/null || true
[[ -f "${ROOT_DIR}/.env" ]] && { set -a; source "${ROOT_DIR}/.env"; set +a; }

BACKUP_DIR="${BACKUP_DIR:-/opt/opic-backup}"
RETAIN_DAYS="${BACKUP_RETAIN_DAYS:-14}"
TODAY="$(date +%F)"
TODAY_DOW="$(date +%u)"   # 7=周日

mkdir -p "${BACKUP_DIR}"
FAILED=0

# 1) PostgreSQL 全库逻辑备份
if docker ps --format '{{.Names}}' | grep -q '^opic-pg$'; then
  if docker exec opic-pg pg_dumpall -U postgres 2>/dev/null \
      | gzip > "${BACKUP_DIR}/pg-${TODAY}.sql.gz.tmp" \
      && mv "${BACKUP_DIR}/pg-${TODAY}.sql.gz.tmp" "${BACKUP_DIR}/pg-${TODAY}.sql.gz"; then
    SIZE="$(du -h "${BACKUP_DIR}/pg-${TODAY}.sql.gz" | cut -f1)"
    ok "pg_dumpall → pg-${TODAY}.sql.gz (${SIZE})"
  else
    rm -f "${BACKUP_DIR}/pg-${TODAY}.sql.gz.tmp"
    fail "pg_dumpall 失败"
    FAILED=1
  fi
fi

# 2) Harbor 数据冷备（周日）
if docker ps --format '{{.Names}}' | grep -q '^harbor-core$' && [[ "${TODAY_DOW}" == "7" ]]; then
  HARBOR_DATA="${HARBOR_DATA_DIR:-/opt/opic/harbor/data}"
  tar -czf "${BACKUP_DIR}/harbor-data-${TODAY}.tar.gz.tmp" -C "$(dirname "${HARBOR_DATA}")" "$(basename "${HARBOR_DATA}")" 2>/dev/null \
    && mv "${BACKUP_DIR}/harbor-data-${TODAY}.tar.gz.tmp" "${BACKUP_DIR}/harbor-data-${TODAY}.tar.gz" \
    && ok "harbor 数据冷备 → harbor-data-${TODAY}.tar.gz" \
    || { rm -f "${BACKUP_DIR}/harbor-data-${TODAY}.tar.gz.tmp"; warn "harbor 冷备失败（非致命）"; }
fi

# 3) 配置与密钥备份（.env 含全部口令 —— 整个部署根的关键配置）
tar -czf "${BACKUP_DIR}/config-${TODAY}.tar.gz" -C "$(dirname "${ROOT_DIR}")" "$(basename "${ROOT_DIR}")/.env" 2>/dev/null \
  && chmod 600 "${BACKUP_DIR}/config-${TODAY}.tar.gz" \
  && ok "配置备份 → config-${TODAY}.tar.gz" \
  || warn "配置备份失败（非致命）"

# 4) 保留策略
DELETED=$(find "${BACKUP_DIR}" -type f \( -name "pg-*.sql.gz" -o -name "harbor-data-*.tar.gz" -o -name "config-*.tar.gz" \) -mtime +"${RETAIN_DAYS}" -print -delete 2>/dev/null | wc -l)
[[ "${DELETED}" -gt 0 ]] && info "保留策略：清理 ${RETAIN_DAYS} 天前备份 ${DELETED} 个"

[[ "${FAILED}" -eq 0 ]] || { fail "备份存在失败项"; exit 1; }
ok "备份完成：$(ls -1 "${BACKUP_DIR}" | grep -c "${TODAY}") 个当日文件 → ${BACKUP_DIR}"
