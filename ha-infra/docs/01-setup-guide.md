# 01 · 安装指南

## 前置条件

| 项 | 要求 |
|---|---|
| 节点 | 3 台（≥40核、≥251G RAM、≥7T NVMe） |
| OS | openEuler 22.03 (133) / Anolis 8.8 (134/141) |
| 网络 | 同网段 55.32.170.0/24，互通 SSH root 免密 |
| DNS | *.opic-dev.ccoe.tech 多 A 记录已配置 |
| 磁盘 | 133/134 各有 ≥2 块空闲 NVMe 分区 |
| 代理 | 出外网需经 dev 代理 `http://99.13.186.254:80` |
| 容器 | Docker 26.1.3 + Compose v2.27.0 已安装 |

## 离线介质清单（`down/` 目录）

| 文件 | 说明 |
|------|------|
| drbd-9.2.20.tar.gz | DRBD 内核模块源码 |
| drbd-utils-9.29.0.tar.gz | DRBD 用户态工具 |
| nfs-ganesha-15.7.tar.gz | NFS-Ganesha 源码 |
| ntirpc-6.3.tar.gz | Ganesha 依赖 |
| harbor-offline-installer-v2.15.2.tgz | Harbor 离线安装器 |
| pigsty-v4.5.0.tgz | Pigsty 发布包 |
| cfssl_1.7.1_linux_amd64 | cfssl 二进制 |
| cfssljson_1.7.1_linux_amd64 | cfssljson 二进制 |

## 安装步骤

### 00 · 前置核查（只读）

```bash
ansible-playbook -i hosts playbooks/00.pre-check.yml
```

门禁：OS/内核/CPU/内存/端口/NTP 全过才进入下一步。

### 01 · DRBD 安装（133/134）

```bash
ansible-playbook -i hosts playbooks/01.drbd.yml
```

操作内容：
1. 安装 kernel-devel（精确匹配运行内核）
2. 源码编译 DRBD 9.2.20 内核模块（需 spatch compat.patch）
3. 编译安装 drbd-utils 9.29.0
4. 渲染 `/etc/drbd.d/nfsdata.res`
5. `create-md --force` → `drbdadm up` → `primary --force`
6. 等待全量同步（7.3T ≈ 2h @1.0GB/s）
7. 格式化 XFS 并挂载 `/srv/nfs/harbor`

⚠ **全量同步需 ≈2 小时**——不要中断。

### 02 · Ganesha 安装（133/134）

```bash
ansible-playbook -i hosts playbooks/02.ganesha.yml
```

操作内容：
1. `/etc/modules-load.d/nfs-ganesha.conf` 写入 nfsd
2. 源码编译 Ganesha 15.7 + ntirpc
3. 渲染 `/etc/ganesha/ganesha.conf`（Export_ID=77, NFSv4.2, TCP）
4. 创建 systemd 单元（disabled——由 keepalived notify 拉起）

### 03 · Keepalived + NFS VIP（133/134）

```bash
ansible-playbook -i hosts playbooks/03.keepalived.yml
```

操作内容：
1. 渲染 `chk-drbd.sh`（只审 VIP 持有者）
2. 渲染 `notify-{master,backup}.sh`
3. 渲染 `keepalived.conf`（vrid 201 / br0 单播 / BACKUP / nopreempt）
4. 添加 ExecStop drop-in（notify-backup on stop）
5. 添加 mount ordering drop-in（mount After=keepalived）
6. `keepalived -t` 验证 → 启用

### 04 · Harbor 部署（三台）

```bash
ansible-playbook -i hosts playbooks/04.harbor-deploy.yml
```

操作内容：
1. 挂载 NFS 数据卷（fstab hard）
2. 解压离线安装器
3. 渲染 harbor.yml（external_database + external_redis）
4. `./prepare` → docker-compose.yml 生成
5. 改 restart: no（P2.1 修复）
6. P2.1 三件套（mount-guard + watchdog service/timer）
7. 等待 healthy + df 影子绑定检查

### 05-09 · 数据层（etcd/PG/Redis/Kafka/MinIO）

```bash
ansible-playbook -i hosts playbooks/05.etcd.yml
ansible-playbook -i hosts playbooks/06.pg-ha.yml
ansible-playbook -i hosts playbooks/07.redis-ha.yml
ansible-playbook -i hosts playbooks/08.kafka.yml
ansible-playbook -i hosts playbooks/09.minio.yml
```

**注**：PG/etcd/Kafka/MinIO 的实际安装委托给 Pigsty ansible（admin 容器内跑 deploy.yml 等顶层 playbook）。本 Ansible 项目做前置容器编排（pigsty-node 镜像构建、容器启动、网络配置）。

### 10 · 应用面（Casdoor/ZITADEL/Gitea/Temporal/NATS）

```bash
ansible-playbook -i hosts playbooks/10.apps.yml
```

每个应用：渲染 docker-compose → render 配置 → `docker compose up -d` → 健康检查。

### 11 · VIBE（133）

```bash
ansible-playbook -i hosts playbooks/11.vibe.yml
```

### 12 · 入口层 Traefik

```bash
ansible-playbook -i hosts playbooks/12.traefik.yml
```

### 13 · 监控

```bash
ansible-playbook -i hosts playbooks/13.monitoring.yml
```

### 14 · 安全

```bash
ansible-playbook -i hosts playbooks/14.security.yml
```

### 15 · 稳态总门禁

```bash
ansible-playbook -i hosts playbooks/15.verify.yml
```

348 格全绿 bad=0 blind=0 = 安装完成。

## 验证

```bash
# Harbor 健康
curl -s http://127.0.0.1:18701/api/v2.0/health | python3 -m json.tool

# 跨节点拉取
docker pull registry.opic-dev.ccoe.tech/opic/test:latest

# PG 集群
patronictl list

# 稳态门禁
bash p6-ha-70-verify-ha-step1.sh all
```
