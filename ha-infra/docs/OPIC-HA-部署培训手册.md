# OPIC HA 基础设施 · 部署培训手册

> 适用：新人培训 + 新环境安装。
> 基准：分支 `feat/aliyun-lab`（2026-11-16 在阿里云 lab 三台 10.26.8.157/158/159 全绿验收）。
> 原仓库骨架版：`main`（ha-infra 角色多为空壳/Pigsty 委托）；本手册描述的是**原生实现版**，全部角色已实测落地。

---

## 1. 架构总览

三台机器承载一套「存储高可用 + 数据面 + 应用面 + 入口 + 监控」的全栈 HA 环境：

```
                 *.opic-dev.ccoe.vip (DNS → 三台任一)
                          │ :443
                  ┌───────▼───────┐
                  │ Traefik ×3    │  二进制+systemd，dynamic 路由/证书
                  └───────┬───────┘
      registry ──► Harbor ×3（haproxy:18700/nginx，数据在 NFS-VIP）
      auth     ──► Zitadel v2.55（apps 两台）
      casdoor  ──► Casdoor（apps 两台）
      git      ──► Gitea 1.22（apps[0]，数据在 NFS）
      vibe     ──► code-server（vibe 节点，/fs = NFS 工作区）
                          │
  ┌───────────────────────┼─────────────────────────────┐
  │ pg_cluster ×3         │ apps ×2          infra ×1(159)│
  │ etcd 2479/2480        │ temporal         Prometheus 9095│
  │ Patroni+PG18 (5433)   │ (casdoor/zitadel/│ Grafana   3000│
  │ Redis+Sentinel×3      │  gitea)          └───────────────┘
  │ Kafka KRaft×3 (RF3)   │
  │ MinIO EC×3 (9000)     │   nats JetStream ×3 (4222/6222/8222/7777)
  └───────────────────────┘
  存储层：DRBD(nfsdata) ×2(157/158) + keepalived VIP 10.26.200.1
          + Ganesha NFS(export /srv/nfs/harbor) → 三台经 VIP 挂载 /opt/opic/harbor/data
```

### 1.1 主机组（inventories/aliyun/hosts.yml）

| 组 | 成员 | 承载 |
|---|---|---|
| harbor | 157,158,159 | Harbor、Traefik、NFS 客户端 |
| nfs_vip | 157(主,pri150), 158(备,pri100) | DRBD + keepalived + Ganesha |
| pg_cluster | 157(primary),158,159 | etcd / Patroni+PG / Redis / Kafka / MinIO / NATS |
| apps | 157,158 | Casdoor / Zitadel / Gitea / Temporal |
| vibe | 157 | code-server |
| infra | 159 | Prometheus / Grafana |

### 1.2 网络要点

- **nebula1 网卡（10.26.8.0/24）**：管理+集群互联，keepalived 单播走它。
- **VPC eth0（10.0.0.x）**：DRBD 数据链路（实测 0.16ms 优于 nebula 隧道）与大介质传输。
- **VIP 10.26.200.1/29**：独立网段，nebula 需配 `unsafeNetworks=10.26.200.0/29`（否则 VIP 不可路由）。NFS 挂载源**必须用 VIP**（随漂移），不能用 real IP。

### 1.3 关键端口

| 服务 | 端口 | 服务 | 端口 |
|---|---|---|---|
| Traefik TLS | 443 | Harbor nginx/haproxy | 18701 / 18700 |
| PG haproxy rw | 5433 | PG 直连 / pgbouncer | 5432 / 6432 |
| etcd client/peer | **2479 / 2480** | Redis / Sentinel | 6379 / 26379 |
| Kafka | 9092(SCRAM) / 9093 | MinIO API/Console | 9000 / 9090 |
| NATS client/cluster/monitor/exporter | 4222/6222/8222/7777 | Temporal gRPC | 7233 |
| Casdoor / Zitadel / Gitea / Gitea-SSH | 8000 / 8080 / 3000 / 2222 | code-server | 8443 |
| Patroni REST | 8008 | Prometheus / Grafana | 9095 / 3000 |
| node_exporter / pg_exporter | 9100 / 9187 | K8s apiserver(外部集群) | 6443 |

---

## 2. 新环境前置条件

1. **机器**：≥3 台 Linux（lab 实测 Alibaba Cloud Linux 3 / al8 内核）。每机建议 ≥4C/15G，**≥3 块空数据盘**（1 块归 DRBD 镜像盘、2 块归 MinIO EC；MinIO 数据目录 `/data/minio/{1...2}`）。
2. **网络**：机器间二层/三层可达；若用覆盖网（nebula），确认 unsafeNetworks 含 VIP 段。DNS 需有 `*.<base_domain>` 通配 A 记录指向三台（或任一 LB）。
3. **SSH**：控制机 root 免密登录三台。
4. **Python**：目标机有 python3（inventory 里 `ansible_python_interpreter` 指到实际路径，需带 `requests`）。
5. **离线介质**：`files/offline/` 已含 DRBD 源码包、etcd、harbor offline installer、minio RPM+mc、ganesha、cfssl、监控四件套等。以下两个 **>100MB 二进制不入 git**（GitHub 硬限），新环境需自行下载放入：
   - `traefik_v3.1.5`（→ traefik.io 官方二进制）
   - `grafana-11.6.0.x86_64.rpm`（→ dl.grafana.com）
6. **镜像预热**：Docker 镜像（harbor 由 offline installer 自带；gitea/zitadel/casdoor/temporal/nats/minio-exporter 走 docker pull）。目标机拉镜像不稳时，用「157 `docker save` → VPC scp → 他机 `docker load`」兜底。

---

## 3. 新环境适配清单（改什么）

以 `inventories/aliyun/` 为模板整目录复制改名（如 `inventories/prod/`），逐项修改：

| 变量（group_vars/all.yml） | 说明 |
|---|---|
| `opic_base_domain` | 平台域名基座（所有 `<svc>.<base>` 路由与通配证书 SAN 由它派生） |
| `opic_nfs_vip` / `keepalived_vip` | VIP 网段；覆盖网需允许该段直路由 |
| hosts.yml 中 `ansible_host`、`peer_address`、`drbd_disk`、`keepalived_unicast_*` | 按新机 IP/盘符填 |
| `ganesha_clients_cidr` | 必须同时含 real IP 网段 **和 VIP 网段**（VIP 持有者自挂源地址是 VIP） |
| `cert_san_hosts` | 通配域名 + 各节点 IP + VIP |
| 各口令：`db_pass`、`redis_pass`、`kafka_admin_password`、`minio_root_password`、`drbd_shared_secret`、zitadel masterkey（**必须 32 字节**）、vibe/grafana 口令 | 生产必须全换 |
| `harbor_hostname` | = `registry.<base>` |
| `media_node_vpc` | 介质中转机 VPC IP |
| `db_host: "{{ ansible_host }}"` | **保持 host 级惰性求值**——harbor-core 在 bridge 容器里，127.0.0.1 指容器自身 |

> 注意：`main` 分支的 `group_vars/all.yml` 含 `[global_vars]` 顶层键 bug，站点变量请写全（inventory 目录内），不依赖仓库根 group_vars。

---

## 4. 安装步骤（playbook 顺序即依赖顺序）

```bash
cd ha-infra
INV=inventories/<site>/hosts.yml        # 以下全部 ansible-playbook -i $INV

ansible-playbook playbooks/00.pre-check.yml   # 资源阈值/端口占用/时钟检查
ansible-playbook playbooks/01.drbd.yml        # DRBD 源码编译+建 res（al8 编译链已修）
ansible-playbook playbooks/02.ganesha.yml     # NFS-Ganesha 源码安装+export
ansible-playbook playbooks/03.keepalived.yml  # VIP+DRBD 探活脚本，VIP 落到 157
ansible-playbook playbooks/14.security.yml    # ★ cfssl CA+通配证书（harbor/traefik 依赖，先建）
ansible-playbook playbooks/05.etcd.yml        # etcd ×3（serial:1 滚动；unit=opic-etcd.service）
ansible-playbook playbooks/06.pg-ha.yml       # Patroni+PG18+haproxy5433+pgbouncer（预建各业务库）
ansible-playbook playbooks/07.redis-ha.yml    # Redis+Sentinel ×3（protected-mode no）
ansible-playbook playbooks/08.kafka.yml       # Kafka KRaft ×3 + SCRAM，断言 RF3
ansible-playbook playbooks/09.minio.yml       # MinIO EC ×3 + 桶（harbor/opic-media/opic-backup）
ansible-playbook playbooks/04.harbor-deploy.yml  # Harbor ×3（详见 §5.2 模板要点）
ansible-playbook playbooks/10.apps.yml        # play1: apps→casdoor,zitadel,gitea,temporal
                                              # play2: pg_cluster→nats(JetStream×3)
ansible-playbook playbooks/11.vibe.yml        # code-server + /fs NFS 挂载
ansible-playbook playbooks/12.traefik.yml     # 443 入口：dynamic tls.yml + harbor/vibe/apps 路由
ansible-playbook playbooks/13.monitoring.yml  # node/pg_exporter ×3 + Prometheus/Graphana@infra
ansible-playbook playbooks/15.verify.yml      # ★ 稳态门禁（见 §6），退出码 0 = 全绿
```

顺序上的硬依赖：
- `14.security` 在 harbor/traefik 之前（证书文件被两边 copy）。
- `05.etcd → 06.pg-ha`（Patroni DCS）；`06 → 04.harbor`（harbor 外部 DB 走本机 5433，且库 `harbor_db` 由 pg-ha 预建）。
- `07.redis → 04.harbor`（sentinel 组网先就绪）。
- `01/02/03 → 04`（三台 `/opt/opic/harbor/data` 必须是 VIP 源 NFS mountpoint）。
- `12.traefik` 放最后段（路由 upstream 需已监听）。

---

## 5. 各层实现要点与实测坑（培训核心）

### 5.1 存储层（DRBD + Ganesha + keepalived）
- al8 上 DRBD 9.2.20 需源码编译：autogen、buildtag seed、drbd-headers submodule、`--without-manual`、**先卸 EPEL drbd-utils(9.28)**（与源码 9.29 路径冲突）、`drbd_disable_dax: true`（al8 厂商 DAX 中间形态不兼容）。
- keepalived 探 DRBD（chk-drbd.sh）+ notify 脚本挂/卸 `/srv/nfs/harbor`。
- **Ganesha CLIENT 必须放行 VIP 网段**：VIP 持有节点经 VIP 自挂 NFS，fstab 才能随 VIP 漂移（否则 VIP 迁移后挂载断）。
- DRBD 走 VPC 内网（比 nebula 隧道快两个量级）；`resync_rate=400M` 时 500G 全量约 25min。

### 5.2 Harbor 2.15.2（prepare 解析器三个坑，全是实测）
1. 外部数据库必须写在 **`external_database.harbor`** 段；裸 `database:` 会被当内部 DB（host 强制 postgresql）。
2. Sentinel redis 只认 **`host:` 逗号串 + `sentinel_master_set`**（`hosts:` 列表键无效）；DB 序号键名 `*_db_index`。
3. 2.15 无默认强取键：`jobservice.max_job_workers/max_job_duration_hours/job_loggers/logger_sweeper_duration`、`notification.webhook_job_max_retry/webhook_job_http_client_timeout`、`log.level/local`——缺任一 prepare 直接 KeyError。
- 2.15 **无 create_db**：`harbor_db` 须在 PG 上预建（pg-ha 已做）。
- 用自研 `opic-harbor.service` + watch timer 管理（installer 自带 unit 的坑：WorkingDirectory 必须是解压产物 `harbor/` 而非 `harbor-installer/`）。
- 排错实录：bridge 容器内 `127.0.0.1`≠宿主机（`db_host` 用 real IP）；harbor-core 连 redis broken pipe = sentinel `protected-mode no`（给 sentinel 加密码没用，go-redis 不对 sentinel 本身 AUTH）；改完配置 **必须 `meta: flush_handlers` 再跑 prepare**，否则 core 里还是旧 env。
- 端到端验收：`docker login registry.<base>:443` → push/pull `opic/smoke-*` 跨节点 → NFS 落盘可见。

### 5.3 数据面
- **etcd**：unit 名 **`opic-etcd.service`**（勿用裸 `etcd.service`——见 §7 K8s 共存事故）。二进制 + cfssl mTLS（证书在 `/opt/opic/etcd/ssl`），serial:1 滚动。
- **Patroni+PG18**：etcd DCS 带 TLS；haproxy 5433=rw、pgbouncer 6432；patroni REST 8008 匿名 `/metrics` 可被 Prometheus 抓。分歧修复路线：pg_rewind 失败（"servers diverged"）→ 停 patroni → `mv /data/pg/18 <备份>` → 起 patroni 自动 basebackup。
- **Redis Sentinel**：`protected-mode no`（sentinel 自身无密码时对所有非 loopback 一律 -DENIED）。master set 名 `mymaster`。
- **Kafka**：KRaft×3，SCRAM-SHA-512，验收用 topic `opic-smoke` RF3 describe。
- **MinIO**：RPM 路线（镜像不可达时），EC 每机 2 盘；`/minio/v2/metrics/cluster` **不支持 Basic Auth**——env `MINIO_PROMETHEUS_AUTH_TYPE=public`。
- **NATS**：JetStream×3（放 pg_cluster 而非 apps）；conf 变更 handler `up -d --force-recreate`；数据目录 chown 1000。**nats-server 2.10 无内置 /metrics**——用官方 `natsio/prometheus-nats-exporter:0.15.0` sidecar(7777)；其 flag 均为布尔，**server URL 是位置参数**，0.15.0 无 `-subsz`（是 `-subz`）。nats:2.10 镜像无 wget/curl → compose 级 healthcheck 会永远 unhealthy，健康把关放 tasks 的 uri 断言。

### 5.4 应用面（五件套 + vibe）
- **Casdoor**：beego 读 `/conf/app.conf`（挂 0644，0600 会挡容器 uid）；DSN 用 `postgres://...?sslmode=disable`（不是 `ssl_mode`）。
- **Zitadel**：v2.3.3 对 env 库名解析有缺陷 → **v2.55.0 + config-YAML + `Admin.ExistingDatabase`**；masterkey **32 字节**；反代终结 TLS → `--tlsMode external`；实例按 ExternalDomain 拦 Host——必须经域名或带 Host 头访问 `/ui/login/`；init 需 DB 角色有 CREATEROLE/CREATEDB；默认 init 账号 `zitadel/Zitadel!1`（首次登录改密）。
- **Gitea**：host 网络时容器内 OpenSSH 会抢宿主 22 → `DISABLE_SSH=true` + 内置 SSH 2222；该版本 `/api/health` 404 → 健康检查用 `/`。
- **Temporal**：auto-setup 1.24 驱动名 **`postgres12`**；host 网络必须 `BIND_ON_IP: "0.0.0.0"` + **`TEMPORAL_BROADCAST_ADDRESS`**（0.0.0.0 监听必须显式 broadcast，env 名以镜像内 config_template 为准）；验收 `tctl cluster health` = SERVING。
- **Vibe**：code-server 二进制 + systemd + `/fs`（NFS `<export>/vibe`，0777 供容器写）。

### 5.5 入口 Traefik v3
- 静态配置 `tls:` **不支持 certificates**——证书放 dynamic 目录 `tls.yml`（certFile/keyFile 指 /etc/traefik/tls），否则出示 TRAEFIK DEFAULT CERT。
- LB healthCheck **只认 2xx**：302/404 都会误摘后端。gitea 探 `/`；casdoor 探测接口回 500 → 不设 healthCheck；zitadel /ui/login 302 → 不设。
- 路由文件按域拆分：`dynamic/{tls,harbor,vibe,apps}.yml`；改完 notify restart traefik。

### 5.6 PKI（14.security）
- cfssl 平台 @157（/opt/cfssl-platform），CA + 通配服务器证书（SAN=通配域名+节点 IP+VIP）+ etcd/patroni 客户端证书；幂等可重跑。
- 产物三台分发：harbor/traefik 用 `tls.pem/tls-key.pem`；etcd 用 `/opt/opic/etcd/ssl/{etcd.pem,etcd-key.pem,ca.crt}`。

### 5.7 监控（13.monitoring，已去 Pigsty 空壳）
- node_exporter ×3(9100)、postgres_exporter ×3(9187，DSN 连本机 5432)、Prometheus @infra(9095——9090 被 minio_console 占)、Grafana RPM @infra(3000)。
- 抓取清单与实存 exporter 一致（haproxy/kafka exporter 未部署就不要写进 prometheus.yml）。
- 验收：`/api/v1/targets` 全部 up（含 nats exporter、minio、patroni）。

---

## 6. 验收门禁

`15.verify.yml`（roles/verify）23+ 项断言，任一红即失败：
DRBD `disk:UpToDate + peer-disk:UpToDate`（该版本 drbdadm 不打印 "Connected"）· 三台 `mountpoint -q /opt/opic/harbor/data` · etcd endpoint health（证书路径 **/opt/opic/etcd/ssl**）· patronictl 1 Leader+≥2 streaming · PG 5433 · sentinel get-master-addr（名字 `mymaster`）· Kafka RF3 · MinIO ready · NATS 组网（**varz 无 peers 列表，组网断言用 routez** unique ip==2）+ exporter 出指标 · Harbor ×3 health · casdoor/zitadel(带 Host 头)/gitea/temporal(tctl)/code-server · **域名冒烟**（registry/auth/casdoor/git/vibe 经 :443）· Prometheus `activeTargets` 无 down · Grafana health。

冒烟注意（从控制机测）：
```bash
# 若本机有 HTTP 代理：--resolve 会被代理吞掉（拿到代理的假 404），必须 -noproxy '*'
curl -sk -noproxy '*' -o /dev/null -w '%{http_code}\n' https://registry.opic-dev.ccoe.vip/v2/
```

---

## 7. 与外部系统共存（真实事故复盘）

lab 中 159 同时是某 K8s v1.36 集群（159/160/161，sealer 风格，eth0 10.0.0.x）的 master-01。**两套 etcd 本身不冲突**（端口 2479/2480 vs 2379/2380、目录/证书/网卡全隔离），真正撞的是：

1. **systemd unit 同名**：K8s 安装器覆盖 `/etc/systemd/system/etcd.service` → OPIC etcd 掉线 → Patroni 角色错乱 + PG 分歧。
   **治本（已做）**：我们 unit 改名 `opic-etcd.service`；角色里 retire 旧 unit 前 slurp 校验 "OPIC DCS" 标记，**绝不触碰外部 etcd.service**。
2. **ingress-nginx hostNetwork 80/443**：调度到 159 时 CNI 的 DNAT 劫持宿主 :443 本地流量（traefik 明明 listen，curl 全 404 + K8s 假证书）。
   **处置**：把 ingress 调度出 159（taint 或 nodeSelector——属 K8s 侧，需对方同意）；若域名 404+nginx 体再现，先 `nft list ruleset | grep 'dnat to'` 定性。

新环境若同机混部其它平台，按「**unit 名带前缀、端口段错开、约定 80/443 归属、DNAT 规则巡检**」四条执行。

---

## 8. 凭据与访问（lab 环境；生产必须全部更换）

| 项 | 值 |
|---|---|
| 域名 | `registry/auth/casdoor/git/vibe.opic-dev.ccoe.vip`（Prometheus `10.26.8.159:9095`、Grafana `10.26.8.159:3000`） |
| Harbor | 管理员 admin（改过密）；项目 `opic` |
| Zitadel | 首次 `zitadel/Zitadel!1`，登录后改密 |
| Vibe/code-server | 口令 `OpicVibe2026Lab` |
| Grafana | admin / `OpicGrafana2026Lab` |
| MinIO | `opicadmin` / `OpicMinio2026Lab` |
| Redis / Kafka / Harbor-DB / PG 管理口令 | `opicRedis2026Lab` / `opicKafka2026Scram` / `OpicHarbor2026Db` / `OpicPg2026Lab` |
| Gitea | 自建账号（内置 SSH 2222） |

---

## 9. 仓库与介质管理

- 分支策略：修订在 `feat/aliyun-lab`（可 PR 到 main）。GitHub 有 **100MB 单文件硬限**：`traefik_v3.1.5`、`grafana rpm` 已入 `.gitignore`，介质保留在部署机磁盘——新环境按 §2.5 自行放置。
- 历史里若混入超限大文件：`git filter-branch --index-filter 'git rm --cached --ignore-unmatch <path>' <base>..<branch>` 剥离（先打备份 tag）。
- 推送大包不稳时：`-c http.postBuffer=524288000`，并分两段推（先推中间 commit 再推 tip）。

## 10. 新人上手路线

1. 读本手册 §1-§3，对着 `inventories/aliyun/` 和 `roles/*/tasks/main.yml` 走一遍代码。
2. 在 lab 跑 `15.verify.yml`，看每项断言对应哪层（roles/verify/tasks/main.yml 即「系统健康自检表」）。
3. 演练一次故障注入：停 157 keepalived → 看 VIP 漂到 158 → NFS 三台仍通 → Harbor 不受影响。
4. 按 §3 复制 inventory 到新环境，按 §4 顺序安装，卡壳先查 §5 对应小节（每条都是踩过的坑）与 §7。
