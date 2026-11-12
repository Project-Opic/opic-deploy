# 07 · 排障指南

## 快速诊断流程

```
1. Harbor /api/v2.0/health → 哪个组件不绿？
2. docker ps → 哪个容器 Down/Restarting？
3. PG → patronictl list → leader 在哪？
4. DRBD → drbdadm status → StandAlone/UpToDate？
5. NFS → findmnt /opt/opic/harbor/data → 挂载在？
6. df 影子 → docker exec ctr df /data → 本地盘/NFS？
```

## 常见故障场景

### S1: Harbor API unhealthy

```bash
curl -s http://127.0.0.1:18701/api/v2.0/health | python3 -m json.tool

# registry 不绿 → NFS 挂载检查
findmnt /opt/opic/harbor/data
# database 不绿 → patroni leader 检查
docker exec -u admin pigsty-admin-ita-m2 patronictl list
```

### S2: 容器 Down/Restarting

```bash
docker ps -a --format '{{.Names}} {{.Status}}' | grep -v Up
# 看 exit code
docker inspect <name> -f '{{.State.ExitCode}} {{.State.Error}}'
# 看日志
docker logs <name> --tail 30
```

### S3: DRBD StandAlone

```bash
drbdadm status nfsdata
# 双侧执行
drbdadm connect nfsdata
# 等待 AL 增量补齐（不触发全量重同步）
```

### S4: systemd 单元 failed（boot 风暴 205/LIMITS）

容器重启后整批单元 exec 失败（205/LIMITS＝systemd exec 层 limits 应用失败）。

```bash
# stop + reset-failed + start 即清（非持久损伤）
systemctl stop <unit>
systemctl reset-failed <unit>
systemctl start <unit>
```

### S5: /run/nologin 残留（admin ssh 被拒）

```
报错: System is booting up. Unprivileged users are not permitted to log in yet.
```

```bash
docker exec <ctr> rm -f /run/nologin
docker exec <ctr> systemctl start systemd-user-sessions
```

### S6: sshd active 但端口不通

```bash
# is-active 对不存在单元也印 inactive（坑候选 528）
systemctl status ssh  # 必须看存在性
ss -ltn | grep :2201  # 必须看端口
```

### S7: nfs-ganesha 起不来（FATAL: nfs_prereq_init）

```bash
# nfsd 内核模块必须先行（§二-15）
cat /etc/modules-load.d/nfs-ganesha.conf
# 应包含 nfsd
modprobe nfsd
systemctl start nfs-ganesha
```

### S8: kafka_exporter down

```bash
# 检查进程
pgrep kafka_exporter
# 检查端口
ss -ltn | grep :9308
# 重启（stop+reset+start 清僵死 job 态）
systemctl stop kafka_exporter
systemctl reset-failed kafka_exporter
systemctl start kafka_exporter
```

### S9: 影子绑定（P2.1 事故）

**现象**：容器内数据路径 df 显示本地盘而非 NFS。

**根因**：dockerd 恢复容器早于 NFS 挂载 → bind 源被建成空目录并被永久钉住。

**检查**：
```bash
docker inspect <ctr> -f '{{range .Mounts}}{{.Source}} => {{.Destination}};{{end}}'
# 凡 Source 含 /dev/mapper（本地盘）而 Destination 本应在 NFS 上 = 影子绑定
```

**修复**：
```bash
# 确认 NFS 挂载在位 → docker compose up -d 重建容器
docker compose -f docker-compose.yml up -d --force-recreate
```

### S10: DRBD 配置分叉读旧态（§78 发现）

**场景**：resync 完成前启动的共享面消费者读到幸存者侧的旧配置。

**处理**：DRBD connect（恢复内容）→ 重启受影响服务。

---

## 日志位置

| 日志 | 路径 |
|------|------|
| HA 事件 | /var/log/opic-ha.log |
| Harbor core | docker logs harbor-core |
| Patroni | docker exec <ctr> journalctl -u patroni |
| Ganesha | /var/log/ganesha.log |
| systemd | journalctl -b -u <unit> |
| Ansible | admin 容器内 ansible.log |

## 排障纪律

1. **按 epoch 对齐日志**（三台 NTP 偏移：133 慢~60s/134 慢~40s/141 快~8h）
2. **is-active 印 inactive 不代表单元存在**（先查 list-unit-files）
3. **systemctl --failed 包含 user@ 瞬态**（排除会话单元）
4. **dockerd 容器恢复会丢 extra_hosts**（silo hosts-prep 依赖它）
5. **resync 完成前启动的消费者可能读到旧态配置**（重启受影响服务）
