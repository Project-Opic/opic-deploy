# 08 · 升级指南

## 原则

- 升级前跑稳态门禁（348/348 基线）
- 每步门禁不过不进下一步
- PG 数据禁 NFS
- 变更前出评估稿供人工审核

## Harbor 升级

```bash
# 1. 备份
docker exec -u postgres pigsty-pg-ita-m2 pgbackrest --stanza=harbor-pg backup

# 2. 停写窗
cd /opt/opic/ha-stack/harbor-installer
docker compose down

# 3. 更新镜像 + harbor.yml
# 修改 harbor.yml → ./prepare → docker compose up -d

# 4. ⚠ 重打 P2.1 三件套（installer 重跑会还原 restart:always）
sed -i 's/restart: always/restart: no/g' docker-compose.yml
# 重打 opic-mount-guard.conf + watchdog

# 5. 验证
curl -s http://127.0.0.1:18701/api/v2.0/health
# df 影子绑定检查
```

## PostgreSQL 大版本升级

```bash
# PG 18 → 新大版本
# 走 pg_upgrade 或逻辑复制（跨大版本只能逻辑）
# 参考：§36 P3c-6 PITR 演练（备份在 MinIO）
```

## DRBD 升级

```bash
# 1. 备份 nfsdata.res
# 2. 先降 Secondary（134）再降 Primary（133）
# 3. 重编译内核模块（新内核 + 新 DRBD 版本）
# 4. 重启模块 → up → connect
# 5. 验证 AL 增量自动补齐
```

## Docker 升级

```bash
# 1. drain 节点（PG leader 漂走）
# 2. apt/yum upgrade docker-ce
# 3. systemctl restart docker
# 4. 确认容器恢复（restart:no 的需手动/看门狗拉起）
# 5. df 影子绑定检查
```

## Pigsty 升级

```bash
# 1. 新 Pigsty release 解压到 /data/pigsty
# 2. pigsty.yml 保持不变（活值唯一源）
# 3. --check 干跑 → 对比 changed 任务列表
# 4. ⚠ deploy.yml 绝不真跑（会抹 HA 手调配置）
```

## 回退

每个升级步骤前：
1. `pgbackrest backup` 增量
2. 记录当前 `drbdadm status` + `patronictl list`
3. 准备回退命令（git revert / docker tag 旧镜像 / restore）
