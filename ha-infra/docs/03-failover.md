# 03 · 故障切换指南

## NFS VIP 切换（133↔134）

### 自动切换（keepalived + notify 脚本）

**触发**：133 宕机/keepalived 停 → 134 keepalived 检测到 MASTER 丢失（~3s）→ notify-master.sh 触发。

**链路**：`drbdadm primary → mount → systemctl start nfs-ganesha`

**恢复回切（nopreempt 手工语义）**：
```bash
# 在原持有者上执行
systemctl stop keepalived   # ExecStop 跑 notify-backup（demote+umount）
# 对端自动升 MASTER（notify-master）
systemctl start keepalived  # 回到 BACKUP
```

### 验证

```bash
# VIP 在哪
ip addr show dev br0 | grep 55.32.170.3

# DRBD 状态
drbdadm status nfsdata

# 客户端自动重连（hard mount 自愈）
df -h /opt/opic/harbor/data
```

### ⚠ 已知坑

| 坑 | 影响 | 处理 |
|---|---|---|
| 接管后 StandAlone | 双侧拒一切入连 | 双侧 `drbdadm connect nfsdata` |
| 配置分叉读旧态 | resync 前启动的消费者读到旧态 | 重启受影响服务 |
| cold restart 后 nfsd 未加载 | ganesha FATAL | /etc/modules-load.d 已含 nfsd |

---

## PG Patroni 切换

### 自动 failover

**触发**：leader 容器/进程宕 → patroni 检测（~1783ms）→ RAFT 选举新 leader。

**验证**：
```bash
docker exec -u admin pigsty-admin-ita-m2 patronictl -c /etc/patroni/patroni.yml list
# Leader 列应指向非 133 的节点
```

**应用影响**：gitea/zitadel 有 ~18s 连接池重连抖动（R10 实测），casdoor 无感。

### 手工 switchover

```bash
docker exec -u admin pigsty-admin-ita-m2 patronictl -c /etc/patroni/patroni.yml \
  switchover --leader harbor-pg-1 --candidate harbor-pg-2
```

### 已知坑

- patroni REST 绑节点 IP 不绑 loopback（坑候选 534）：`:8008/primary` 探节点 IP 不探 127.0.0.1
- pg_stat_replication 只在 leader 上有行；replica 上 = 0（§79 同款拓扑后果）

---

## Harbor 节点故障

### 单节点 Harbor 停

其他两台 Harbor 继续服务（DNS 多 A 轮询 + 三后端 haproxy）。无需操作。

### 133（中心域宿主）traefik 停

双实例域（casdoor/gitea 等）经 134/141 入口保持 200（§78 双活收益实测）。
单实例 133 域 + registry.* 三口断（设计内）。

恢复：`docker start opic-traefik`

---

## etcd/Kafka/Redis 单节点故障

各组件 RAFT 仲裁 ≥2/3，单节点故障自动接管，无需人工干预。

```bash
# 验证
etcdctl --endpoints=127.0.0.1:2479 endpoint health
redis-cli -p 6379 -a <pw> ping
/opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server 127.0.0.1:9092
```

---

## 整台 133 宕机（P8-B 已验证）

| 组件 | 接管 | 耗时 |
|------|------|------|
| NFS VIP → 134 | keepalived + notify-master | ~1s |
| DRBD Primary → 134 | notify-master 内 | ~1s |
| PG leader → 134/141 | Patroni RAFT | ~1783ms |
| Harbor on 133 | 容器全部下线 | — |
| 中心域双实例 | 134 实例继续服务 | 200 保持 |
| VIBE | 下线（133 独占） | 恢复需 133 回来 |

**133 回来后**：
1. keepalived BACKUP 不抢 VIP（nopreempt）
2. DRBD attach + 同步 AL 增量
3. PG rejoin 为 replica
4. ⚠ resync 完成前启动的消费者可能读到旧态配置 → 重启受影响服务（§78 实测 gitea app.ini 端口分叉）

---

## 恢复后检查清单

```bash
# 1. DRBD 双侧 UpToDate
drbdadm status nfsdata

# 2. Harbor healthy
curl -s http://127.0.0.1:18701/api/v2.0/health

# 3. Patroni 三成员
patronictl list

# 4. 稳态门禁
bash p6-ha-70-verify-ha-step1.sh all
# 348/348 bad=0 blind=0

# 5. 影子绑定检查
for c in harbor-core harbor-jobservice registry; do
  docker exec $c df -h /data | tail -1
done
```
