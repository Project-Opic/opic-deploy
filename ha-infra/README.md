# OPIC HA-step1 — Ansible 化安装（kubeasz 风格）

## 用法

```bash
cp hosts.example hosts
# 编辑 hosts（IP/主机名/角色标注）

# 只做前置核查（H0，只读）
ansible-playbook -i hosts playbooks/00.pre-check.yml

# 分步安装（推荐：每步确认后再走下一步）
ansible-playbook -i hosts playbooks/01.drbd.yml
ansible-playbook -i hosts playbooks/02.ganesha.yml
ansible-playbook -i hosts playbooks/03.keepalived.yml
# ... 后续按序

# 全量（不推荐——停写窗步骤需人工确认）
ansible-playbook -i hosts playbooks/all.yml
```

## 角色映射（kubeasz 风格 → HA-step1 组件）

| Playbook | 角色 | 对应 runbook | 说明 |
|---|---|---|---|
| 00.pre-check | pre-check | H0 | OS/NTP/磁盘/端口/防火墙 只读核查 |
| 01.drbd | drbd | P2a | DRBD 9.2.20 内核模块编译 + nfsdata 资源 |
| 02.ganesha | ganesha | P1/P2a | NFS-Ganesha 15.7 源码编译 + systemd |
| 03.keepalived | keepalived | P2a/P2b | NFS VIP .3 + chk-drbd track_script |
| 04.harbor-deploy | harbor | P4/P5 | Harbor ×3 external_database/redis |
| 05.etcd | (pigsty) | P3a | etcd ×3 (Pigsty etcd role) |
| 06.pg-ha | (pigsty) | P3c | Patroni + PG18 ×3 (Pigsty deploy.yml) |
| 07.redis-ha | redis-ha | P3b | Redis 7 + Sentinel ×3 |
| 08.kafka | kafka | 阶段2-C | Kafka KRaft ×3 SCRAM |
| 09.minio | minio | 阶段2-E | MinIO 6盘 EC:3 ×3 |
| 10.apps | casdoor/zitadel/gitea/temporal/nats | 阶段3 | 应用面 5 件 |
| 11.vibe | vibe | 阶段2-D | VIBE code-server @133 |
| 12.traefik | traefik | P6 | 入口层 Traefik ×3 |
| 13.monitoring | monitoring | §35 | Grafana + VL + Alertmanager |
| 14.security | security | §四 | cfssl PKI + SCRAM |
| 15.verify | verify | H10 | 稳态总门禁 348 格 |

## 已有实现状态

| 角色 | defaults | tasks | templates | 完整度 |
|---|---|---|---|---|
| pre-check | ✅ | ✅ | — | ✅ 完整 |
| drbd | ✅ | ✅ | nfsdata.res.j2 | ✅ 完整 |
| keepalived | ✅ | ✅ | conf+chk+notify×2 | ✅ 完整 |
| ganesha | ✅ | ✅ | ganesha.conf.j2 | ✅ 完整 |
| harbor | 骨架 | 骨架 | — | ⚠ 待填 |
| pg-ha | 骨架 | 骨架 | — | ⚠ 委托 Pigsty |
| redis-ha | 骨架 | 骨架 | — | ⚠ 待填 |
| etcd | 骨架 | 骨架 | — | ⚠ 委托 Pigsty |
| kafka | 骨架 | 骨架 | — | ⚠ 待填 |
| minio | 骨架 | 骨架 | — | ⚠ 待填 |
| casdoor | 骨架 | 骨架 | — | ⚠ 待填 |
| zitadel | 骨架 | 骨架 | — | ⚠ 待填 |
| gitea | 骨架 | 骨架 | — | ⚠ 待填 |
| temporal | 骨架 | 骨架 | — | ⚠ 待填 |
| nats | 骨架 | 骨架 | — | ⚠ 待填 |
| vibe | 骨架 | 骨架 | — | ⚠ 待填 |
| traefik | 骨架 | 骨架 | — | ⚠ 待填 |
| monitoring | 骨架 | 骨架 | — | ⚠ 待填 |
| security | 骨架 | 骨架 | — | ⚠ 待填 |
| verify | — | 占位 | — | ⚠ 待填 |

## 文档目录（docs/）

| 文档 | 内容 |
|------|------|
| [00-architecture.md](docs/00-architecture.md) | 架构总图、节点角色、组件关系、数据流、已知限制 |
| [01-setup-guide.md](docs/01-setup-guide.md) | P0→P8 分步安装指南（每步关键命令＋门禁＋注意事项） |
| [02-operations.md](docs/02-operations.md) | 日常运维（门禁/Harbor/PG/Redis/Kafka/DRBD/监控/日志/定时任务） |
| [03-failover.md](docs/03-failover.md) | 故障切换（NFS VIP/PG Patroni/Harbor 节点/etcd/Kafka/Redis/整台宕机/恢复清单） |
| [04-backup-restore.md](docs/04-backup-restore.md) | 备份恢复（pgBackRest/DRBD/配置备份/已验证场景） |
| [05-certificates.md](docs/05-certificates.md) | 证书管理（PKI 架构/Harbor TLS/etcd 证书/CA 确权规则/有效期） |
| [06-monitoring.md](docs/06-monitoring.md) | 监控指南（架构/Grafana 面板/告警/稳态门禁 348 格/注意事项） |
| [07-troubleshooting.md](docs/07-troubleshooting.md) | 排障指南（S1~S10 十个场景＋日志位置＋排障纪律五条） |
| [08-upgrade.md](docs/08-upgrade.md) | 升级指南（Harbor/PG/DRBD/Docker/Pigsty/回退） |
| [09-faq.md](docs/09-faq.md) | FAQ（15 条常见问题含排查命令） |

## 与既有 Pigsty 的关系

- PG/etcd/Redis/Kafka/MinIO 委托给 Pigsty 自身 ansible（admin 容器内）
- 本仓库的角色对这些件做**前置容器编排**（pigsty-node 镜像构建、容器启动、网络配置）
- Pigsty 的 `deploy.yml` 只覆盖到 PGSQL INIT；后续 redis/kafka/vibe/docker 需单独 playbook

## 参考文档

- runbook: `harbor-ha-评估方案.md` §17~§84（完整执行账 6321 行）
- 完成度报告: `P6l-HA-step1-完成度报告.md`（284 行，审计 fail=0）
- 任务定义: `P6h-HA-step1-任务定义.md`（132 行）
- 演练计划: `P6n-P8-刷新版演练计划.md`（63 行）
