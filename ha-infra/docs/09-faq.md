# 09 · FAQ

### Q: 新节点加入集群需要做哪些事？

1. P0 前置清理（sealos/k8s 残留退役）
2. Docker 安装 + 配置
3. NFS 客户端挂载（fstab → VIP .3）
4. Harbor 部署（prepare + up -d + P2.1 三件套）
5. pg 容器启动（pigsty-node 镜像 + patronictl join）
6. Traefik 部署 + 路由

详见 runbook P5（§四-P5）。

### Q: Harbor 上的镜像为什么突然"凭空消失"？

**这是 NFS VIP 漂移到了没有 DRBD 数据的节点（141）或 ganesha 导出了空目录**。按设计 NFS VIP 只在 133↔134 之间漂移。检查：

```bash
ip addr show dev br0 | grep 55.32.170.3
mountpoint /srv/nfs/harbor && find /srv/nfs/harbor -maxdepth 1 | head -3
# 应有 harbor 数据目录
```

### Q: 中心域（casdoor 等）突然 503 "no available server"？

**双实例域**：casdoor/gitea/zitadel/temporal 跑在 133+134，经对侧入口访问。若对侧 traefik 标记后端 unhealthy → 检查对侧实例容器状态和 /api/healthz。

**DRBD 分叉配置读旧态**（§78 发现）：resync 完成前启动的消费者可能读到旧态配置 → `drbdadm connect` 后重启受影响服务。

### Q: patronictl switchover 之后 gitea/zitadel 有一段时间 503？

**正常**。R10 实测：PG 切主后 gitea/zitadel 有 ~18s 连接池重连抖动。等待自愈（连接池自动重连），无需重启。

### Q: pg_stat_replication 在 replica 上查不到行？

**正常**。`pg_stat_replication` 只在 leader（主库）上有行——显示的是"谁在连我"。replica 上查会返回 0 行。要查复制状态需在 leader 上执行。

### Q: 三台 NTP 不同步怎么排障？

**§35 已报站点**（NTP 源不可达）。排障时**按 epoch 对齐日志时间戳**：

```bash
date +%s   # 取 epoch 再换算
```

三台偏移：133 慢~60s / 134 慢~40s / 141 快~8h。不要直接比较墙上钟。

### Q: systemd --failed 显示很多 user@1000 之类的单元？

**瞬态**。这是 ssh 会话的 user@/user-runtime-dir 单元，不是服务故障。门禁 UNITS 尺已排除（§76 拓扑化）。静置后 `systemctl reset-failed` 即清。

### Q: DRBD 状态查 /proc/drbd 怎么没有资源信息？

**正常**。DRBD9 的 /proc/drbd 只显示版本头（§78 实测）。真实状态用 `drbdadm status` 查看。

### Q: 怎么判断 DRBD resync 是否完成？

```bash
drbdadm status nfsdata
# 双侧 disk:UpToDate + peer-disk:UpToDate + 无 SyncTarget/SyncSource = 完成
```

### Q: pgbouncer show servers 返回 0 行？

**取决于 leader 位置**。pgbouncer `show servers` 显示本节点→PG 的打开连接池。leader≠本节点时池自然空闲 → 0 行是拓扑后果非故障。

### Q: Harbor installer 重跑后 redis/jobservice 变 unhealthy？

**P2.1 事故复现**。installer 重跑会还原 `restart: always` → dockerd 恢复容器早于 NFS 挂载 → redis/jobservice 绑到本地空目录。

**修复**：
```bash
sed -i 's/restart: always/restart: no/g' docker-compose.yml
docker compose up -d --force-recreate
# 验证 df 影子绑定
```

### Q: 如何判断哪些服务在重启后需要手动重启？

参考 §76 拓扑化后的模式：
- **Requires=挂载单元的件**在挂载失败后被跳过且无自动重试
- **"起了没 enable"的件**（kafka_exporter 裸进程、code-server 无 unit）
- **dockerd 恢复丢 extra_hosts** 的件（silo hosts-prep）
- **resync 完成前启动的 DRBD/NFS 共享面消费者**（读旧态配置）

建议重启窗 G2 闸加「失败单元逐个 stop/reset/start 复活循环」。

### Q: keepalived notify-master.sh 执行失败会怎样？

keepalived 不会撤销 VIP——VIP 留在故障节点但 ganesha 没起 → chk_drbd track_script 检测到（role:Primary + mountpoint + ganesha 任一不过）→ FAULT → VIP 交棒给对端。对端 notify-master 走正常接管流程。

### Q: DRBD shared-secret 在哪？能看吗？

在 `/etc/drbd.d/nfsdata.res` 的 `net { shared-secret "..."; }` 行。**不要 cat 整个文件**（会暴露 secret）。用 `drbdadm show` 或只 grep secret 行的 md5 确认双端一致。2026-10-09 已重生成（未落终端）。

### Q: 三台 NTP 不同步影响什么？

不影响服务运行，但影响日志排障。三台偏移：133 慢~60s / 134 慢~40s / 141 快~8h。**按 epoch 对齐日志**，不要直接比较墙上钟。已报站点（§35）。
