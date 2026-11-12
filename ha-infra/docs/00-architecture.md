# 00 · 架构总览

## 集群拓扑

```
                DNS: *.opic-dev.ccoe.tech → A: 133,134,141（站点 DNS 轮询）
                                 │
   ┌─────────────────────────────┼─────────────────────────────┐
   │ 55.32.170.133 (ita-m2)     55.32.170.134 (ita-m3)       55.32.170.141 (phdk8s141)
   │ ┌────────────┐   ┌────────────┐                   ┌────────────┐
   │ │ Traefik:443│   │ Traefik:443│                   │ Traefik:443│
   │ │ Harbor:18701   │ Harbor:18701│                   │ Harbor:18701
   │ ├────────────┤   ├────────────┤                   ├────────────┤
   │ │ PG18+Patroni   │ PG18+Patroni│                   │ PG18+Patroni
   │ │ Redis+Sentinel │ Redis+Sentinel│                 │ Redis+Sentinel
   │ │ etcd:2479      │ etcd:2479    │                  │ etcd:2479
   │ │ Kafka:9092     │ Kafka:9092   │                  │ Kafka:9092
   │ │ Casdoor:8000   │ Casdoor:8000 │                  │              │
   │ │ ZITADEL:8080   │ ZITADEL:8080 │                  │              │
   │ │ Gitea:3000     │ Gitea:3000   │                  │              │
   │ │ Temporal:7233  │ Temporal:7233│                  │              │
   │ │ NATS:4222      │ NATS:4222    │                  │              │
   │ │ VIBE:8443      │              │                   │              │
   │ ├────────────┤   ├────────────┤                   ├────────────┤
   │ │ 本地 NVMe      │   │ 本地 NVMe    │                  │ /data1 ext4  │
   │ └────────────┘   └────────────┘                   └────────────┘
   │                                                        ┌────────────┐
   │                                                        │ pigsty-infra│
   │                                                        │ Grafana:3000│
   │                                                        │ nginx:28080 │
   │                                                        │ silo:9000   │
   │                                                        └────────────┘
   │
   ├── DRBD9 res=nfsdata  133(Primary) ↔ 134(Secondary)  [141 不参与]
   │   → XFS → NFS-Ganesha V15.7 → VIP 55.32.170.3
   │   → 三台 Harbor 挂载 VIP:/srv/nfs/harbor → /opt/opic/harbor/data
```

## 节点角色

| 节点 | IP | 主机名 | OS | HA 角色 | 存储角色 |
|------|-----|--------|-----|---------|---------|
| 133 | 55.32.170.133 | ita-m2 | openEuler 22.03 | Harbor 主节点＋中心域＋DRBD Primary＋admin | DRBD Primary (nvme2n1p2) |
| 134 | 55.32.170.134 | ita-m3 | Anolis 8.8 | Harbor 应用＋中心域＋DRBD Secondary＋admin | DRBD Secondary (nvme1n1p2) |
| 141 | 55.32.170.141 | phdk8s141 | Anolis 8.8 | infra 监控＋pgBackRest 仓库＋pigsty admin | /data1 ext4 (1.4T) |

## 核心组件关系

| 层 | 组件 | HA 方式 | 数据面 |
|---|---|---|---|
| 镜像存储 | DRBD + NFS-Ganesha + VIP .3 | 主备（keepalived nopreempt） | DRBD→XFS（133/134 NVMe） |
| 数据库 | Patroni + PG18 + etcd + pgbouncer + haproxy | leader 选举（RAFT） | 本地 NVMe（禁 NFS） |
| 缓存 | Redis 7 + Sentinel | 哨兵仲裁 ×3 | 本地 NVMe |
| DCS | etcd ×3 (Pigsty 管理内) | RAFT | 容器内 |
| 消息 | Kafka KRaft ×3 combined | RAFT | 容器内 |
| 对象存储 | MinIO EC:3（6盘×3节点） | EC 纠删码 | 本地 NVMe |
| 入口 | Traefik ×3 | DNS 多 A 记录（无 VIP） | 无状态 |
| IdP | Casdoor ×2 + ZITADEL ×2 | 双副本 + 外部 PG | 本地 |

## 数据流

```
docker pull registry.opic-dev.ccoe.tech/opic/xxx
  → DNS 轮询到 133/134/141 之一
  → 该节点 Traefik :443
  → 路由 Host(registry.*) → Harbor :18701
  → Harbor registry 读数据
  → /opt/opic/harbor/data/registry/...
  → NFS mount → VIP .3 → Ganesha (Primary 节点)
  → XFS on /dev/drbd0 → DRBD 同步到对端
```

## 已知限制

| 限制 | 影响 |
|------|------|
| DRBD 仅 133↔134 | 133+134 同时故障 = 镜像数据不可用 |
| Ganesha 只能单活 | 主备切换 ≈7s；写入面只在 Primary |
| 入口 VIP .4 未实装 | DNS 轮询无健康检查剔除；单节点故障需手动处理 |
| 双实例域仅在 133+134 | 133 traefik 停 = 133 单实例域三口断（双实例域经 134 保持） |
| 无 Pacemaker | 141 缺 resource-agents；用 keepalived 替代 |
