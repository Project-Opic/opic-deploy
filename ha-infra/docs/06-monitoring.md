# 06 · 监控指南

## 监控架构

| 层 | 组件 | 节点 | 端口 | 用途 |
|---|---|---|---|---|
| infra | Grafana | 141 | 3000 | 面板（root_url=/ui/） |
| infra | nginx portal | 141 | 28080/28443 | Pigsty 门户 |
| infra | VictoriaLogs | 141 | 9428 | 日志聚合 |
| infra | VictoriaTraces | 141 | 10428 | 链路追踪 |
| infra | Alertmanager | 141 | 9059/9093 | 告警 |
| infra | blackbox_exporter | 141 | 9115 | 黑盒探测 |
| pg 容器 | node_exporter | 三台 | 9100 | 节点指标 |
| pg 容器 | pg_exporter | 三台 | 9630 | PG 指标 |
| pg 容器 | redis_exporter | 三台 | 9121 | Redis 指标 |
| pg 容器 | haproxy exporter | 三台 | 9101 | haproxy 指标 |
| pg 容器 | nginx exporter | 三台 | 9113 | nginx 指标 |
| 宿主 | kafka_exporter | 133(缺)/134/141 | 9308 | Kafka lag |

## Grafana 面板

访问：`http://55.32.170.141:3000` 或 `https://grafana.opic-dev.ccoe.tech/ui/login`

| 面板 | 用途 |
|------|------|
| PG Overview | 集群状态、连接数、复制延迟 |
| PG Node | 单节点 CPU/内存/磁盘/IO |
| Redis Overview | 主从状态、命中率、内存 |
| Kafka Exporter | consumer lag、broker 状态 |
| HAProxy | 前后端连接、health status |
| Node Exporter | 系统层 CPU/内存/磁盘/网络 |

## 告警

Alertmanager 已集群化（三节点）。通知集成见 §55（#122）。

## 稳态门禁（全量体检）

```bash
cd /Users/admin/Documents/github/opic-ai-devops/ha
bash p6-ha-70-verify-ha-step1.sh all

# 348 格覆盖：
# APP(36) + ENTRY(47) + ETCD(14) + HST(37) + KAFKA(30)
# + META(22) + MINIO(18) + OBS(35) + PG(50) + REDIS(59) = 348

# 门禁拓扑不变量（§76 拓扑化后自动跟随）：
# NFSHA holders=1 / p2049_on_vip / ganesha_on_vip / n141_2049=0
# PGBADMINL server_rows（leader 侧池行数）
```

## ⚠ 门禁注意事项

- 动过观测件后要等 ≥2 个抓取周期再跑总门禁（坑 386）
- node=ALL 行的 weight 即最少发射行数下界（坑候选 531）
- UNITS 排除 user@/session 单元（ssh 假红，§79）
