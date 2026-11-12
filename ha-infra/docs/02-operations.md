# 02 · 运维指南

## 稳态门禁

```bash
cd /Users/admin/Documents/github/opic-ai-devops/ha
bash p6-ha-70-verify-ha-step1.sh all
# 348 格全绿 bad=0 blind=0 = 健康
```

## Harbor 健康检查

```bash
curl -s http://127.0.0.1:18701/api/v2.0/health | python3 -m json.tool
# status=healthy 且各组件全绿

# df 影子绑定检查（P2.1 事故判定）
for c in harbor-core harbor-jobservice registry; do
  docker exec $c df -h /data 2>/dev/null | tail -1
done
# 凡出现 /dev/mapper（本地盘）而该路径本应在 NFS 上 = 影子绑定
```

## PG 集群操作

```bash
# 集群状态
docker exec -u admin pigsty-admin-ita-m2 patronictl -c /etc/patroni/patroni.yml list

# leader 位置（patroni REST 探节点 IP，不绑 loopback）
for n in 133 134 141; do
  echo "node$n: $(curl -sk -o /dev/null -w '%{http_code}' http://55.32.170.$n:8008/primary)"
done
# 200 = leader，503 = replica

# 手工 switchover
docker exec -u admin pigsty-admin-ita-m2 patronictl -c /etc/patroni/patroni.yml switchover

# 复制延迟
docker exec pigsty-pg-ita-m2 psql -U postgres -c \
  "SELECT application_name, state, sync_state, replay_lag FROM pg_stat_replication"
```

## Redis 操作

```bash
# 集群状态
redis-cli -p 6379 -a <password> info replication
# role:master + connected_slaves:2 = 正常

# Sentinel 状态
redis-cli -p 26379 -a <password> info sentinel
```

## Kafka 操作

```bash
# consumer lag
/opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server 127.0.0.1:9092 \
  --command-config /etc/kafka/admin.properties --describe --all-groups

# 主题列表
/opt/kafka/bin/kafka-topics.sh --bootstrap-server 127.0.0.1:9092 \
  --command-config /etc/kafka/admin.properties --list
```

## DRBD/NFS 操作

```bash
# 状态
drbdadm status nfsdata
# 正常 = role:Primary/Secondary + disk:UpToDate + peer-disk:UpToDate

# StandAlone 恢复
drbdadm connect nfsdata  # 双侧执行

# VIP 持有者
ip addr show dev br0 | grep 55.32.170.3

# Ganesha 进程
pgrep ganesha.nfsd

# 切换（nopreempt 手工回切语义）
# 持有者: systemctl stop keepalived → ExecStop 跑 notify-backup
# 对端: 立即 MASTER → notify-master (up→primary→mount→ganesha)
# 原持有者: systemctl start keepalived → BACKUP
```

## 监控面板

```bash
# Grafana（141 infra）
curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3000/api/health
# 200 = 正常

# Pigsty 门户
curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:28080/
# 200/301

# VictoriaLogs
curl -s http://127.0.0.1:9428/select/logsql/query -d 'query={job="kafka"}' | tail -3
```

## 证书轮换

```bash
# Harbor 证书（133 签发）
cd /opt/cfssl-platform
./scripts/issue-cert.sh csr/opic-harbor-server-csr.json
# 产物 → /dev/shm/opic-ha-sign → 分发三台 → ./prepare → restart
```

## 日志查看

```bash
# HA 事件日志
tail -20 /var/log/opic-ha.log

# pg 日志
docker exec pigsty-pg-ita-m2 tail -20 /pg/data/pg18/log/postgresql-*.log

# Harbor 组件日志
docker logs harbor-core --tail 20
```

## 定时任务

| 任务 | 时间 | 位置 | 说明 |
|------|------|------|------|
| pgBackRest 全量 | 03:30 UTC 每日 | pg 容器 crontab | pgbackrest backup --type full |
| pgBackRest 增量 | 手动/演练前 | 手动 | pgbackrest backup (incr) |
| opic-harbor-watch | 30s 循环 | systemd timer | compose up -d 幂等 |
| apt-daily | — | 已 mask（§76） | 受管容器不应自升级 |
