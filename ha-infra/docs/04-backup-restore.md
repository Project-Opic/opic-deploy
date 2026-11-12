# 04 · 备份与恢复

## 备份策略

| 数据 | 备份方式 | 频率 | 载体 | 恢复 |
|------|----------|------|------|------|
| PG 数据库 | pgBackRest → MinIO (141 silo) | 03:30 UTC 每日全量 + 按需增量 | S3-compatible | PITR |
| Harbor 镜像 | DRBD 同步复制 | 实时 | 对端 NVMe | 切 Primary |
| Redis | RDB dump（NFS 上 dump.rdb） | 按配置 | DRBD 对端 | 重启自动载入 |
| Kafka | 无（消息队列，生产不备份） | — | — | — |
| Harbor 配置 | harbor.yml + prepare 产物 | 变更时手动 | NFS + git | 直接恢复 |

## pgBackRest 操作

### 手动全量备份

```bash
docker exec -u postgres pigsty-pg-ita-m2 \
  pgbackrest --stanza=harbor-pg backup
```

### 手动增量备份

```bash
docker exec -u postgres pigsty-pg-ita-m2 \
  pgbackrest --stanza=harbor-pg backup --type=incr
```

### 查看备份列表

```bash
docker exec -u postgres pigsty-pg-ita-m2 \
  pgbackrest --stanza=harbor-pg info
```

### 恢复（PITR）

```bash
# 参考：§36 P3c-6 跨时间线 PITR 演练（已验证）
# 恢复到指定时间点
docker exec -u postgres pigsty-pg-ita-m2 \
  pgbackrest --stanza=harbor-pg \
  --delta --type=time "--target=2026-11-11 06:00:00" restore

# Patroni 会自动启动恢复
```

## DRBD 数据恢复

### 单节点故障（133 Primary 宕机）

1. 134 自动接管（notify-master）
2. 133 修复后重启 → notify_backup 自动 attach + secondary
3. AL 增量自动补齐（drbdadm connect 即触发）
4. 验证：`drbdadm status nfsdata` 双侧 UpToDate

### 双节点故障（极端场景）

133+134 同时故障 = 镜像数据不可用（已知限制 §一-1）。
141 Harbor 进程活着但数据空目录 → 表现为全集群"镜像凭空消失"。

**恢复**：
1. 恢复 133（先起）→ DRBD 从磁盘重新挂载
2. 134（后起）→ DRBD 从 133 同步
3. 验证双侧 UpToDate 后启动 ganesha

### Harbor 镜像丢失后的兜底

如果 DRBD 数据彻底丢失，可从 Harbor 的远端源（如 Docker Hub）重新 pull 所有镜像。

## 配置备份

| 文件 | 备份方式 | 频率 |
|------|----------|------|
| pigsty.yml | pigsty-admin 双容器同步 | 每次变更手动 |
| harbor.yml | git commit（C2 patch） | 每次变更 |
| drbd.res | tar → /root/ | 变更时 |
| .env | gen-env.sh --force 生成 | 变更时 |
| keepalived.conf | git commit | 变更时 |

## 已验证场景

| 场景 | 验证时间 | 结果 |
|------|----------|------|
| 跨 TL PITR | §36 P3c-6 | ✅ 2026-10-10 |
| 133→134→133 回切 | §四-P2 ⑥ | ✅ 2026-10-09 |
| 133 冷重启 DRBD AL 增量 | §四-P2 ⑦ | ✅ 2026-10-09 |
| P8-B 后 DRBD 分叉配置修复 | §78 | ✅ 2026-11-11 |
| pgBackRest S3 双点（full+incr） | §77 | ✅ 2026-11-11 |
