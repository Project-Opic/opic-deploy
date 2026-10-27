# opic-deploy

> English: [README.md](README.md)

[![License](https://img.shields.io/badge/License-MulanPSL--2.0-2E7D32)](LICENSE)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)](stacks/nats/docker-compose.yml)
[![NATS](https://img.shields.io/badge/NATS-2.14-27AAE1)](stacks/nats)
[![Temporal](https://img.shields.io/badge/Temporal-1.29-6E56CF)](stacks/temporal)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-4169E1?logo=postgresql&logoColor=white)](stacks/database)

[文档](#文档) | [架构](#架构) | [使用](#使用) | [部署](#部署) | [路线图](#路线图) | [许可证](#许可证)

**opic-deploy 是 OPIC 开放智能算力平台的统一部署与运维仓库**：一个 `.env` 配置源、每个组件一个 `stacks/<name>/`、一套离线介质。各堆栈通过外部 Docker 网络 `opic-net` 互联，所有组件参数只从唯一配置源取值——不制造第二份真相。

仓库侧关注的是「分布式平台如何不漂移地在现场起得来」：端口、口令、数据目录收敛到一个文件；事件编目、订阅关系、编排结构合法性等语义权威留在能力中心，本仓库只提供第 3 层执行器的已验证默认组合。

本仓库包含带健康门禁的第一步基础设施安装器、逐组件 Docker Compose 堆栈、锁定的组件版本、可观测套件、离线介质与部署顺序规范。

## 文档

| 文档 | 内容 |
|---|---|
| [第一步·基础设施安装](docs/第一步-基础设施安装.md) | 第一步基础设施安装说明 |
| [第一步·容器化部署](docs/第一步-容器化部署.md) | 第一步的容器化部署 |
| [运维手册 step1](docs/运维手册-step1.md) | 第一步运维手册 |
| [生产部署方案](docs/生产部署方案.md) | 生产部署方案 |
| [O-SYS 集成说明](docs/O-SYS-集成说明.md) | 与能力中心的语义对应与四条硬边界 |
| [部署顺序](docs/部署顺序.md) | 部署顺序、J1~J7 排序判据与逐条理由——本仓单一事实源 |
| [techbase-ops](docs/techbase-ops.md) | techbase 运维笔记 |

## 架构

opic-deploy 采用 **单一配置文件 + 分层 stack + 离线介质** 的组织方式：

- **`.env`** —— 唯一配置源。`bin/gen-env.sh` 生成它并填充复杂度合规的口令；所有 compose 文件与脚本只从这里取值。
- **`stacks/<name>/`** —— 每个组件一个堆栈，含 `docker-compose.yml` 与可选的 `post-install.sh`（校验组件并打印接入信息）。
- **`bin/`** —— 编排层：`install-step1.sh`（F0~F8，幂等）、`verify-step1.sh`（八项健康门禁，可随时重跑）、`teardown-step1.sh`（逆序停止，数据保留），以及生产运维用的 `gen-certs.sh` 与 `backup-prod.sh`。
- **`observability/`** —— techbase 可观测套件：Grafana 看板、vmalert 规则、file-sd 目标与安装脚本。
- **`offline-kit/`** —— 离线介质：`pack.sh` 打包、`install.sh` 消费，含 demo SSO compose 文件。

部署路径：

- 第一步（推荐）：`bash bin/install-step1.sh` 按顺序拉起基础设施——主机前置 → 数据与身份地基 → 第 3 层中间件 → 观测收口。
- 逐栈部署：`cp .env.example .env && vim .env`，然后 `cd stacks/<name> && docker compose up -d && bash post-install.sh`。
- 启动正序、停止逆序——完整顺序、七条 J1~J7 判据与逐条理由见 [`docs/部署顺序.md`](docs/部署顺序.md)。

语义口径：这里的组件只是**执行器**。事件编目、订阅关系、编排结构合法性等语义权威归能力中心（见 [`docs/O-SYS-集成说明.md`](docs/O-SYS-集成说明.md)）。

### 核心能力

| 能力 | 说明 |
|---|---|
| **事件总线堆栈** | NATS Server + JetStream，强制 user/password 鉴权，`post-install.sh` 校验（客户端 4222，监控 8222） |
| **流程引擎运行堆栈** | Temporal Server + PostgreSQL 16 + Web UI + admin-tools，首启自动建库表 schema 并创建业务命名空间（gRPC 7233，UI 8233） |
| **基础设施堆栈** | database / redis / traefik / zero-trust（ZITADEL）/ casdoor / registry（Harbor），遵循同一配置纪律 |
| **第一步安装器** | F0~F8 一键编排（幂等），`--no-registry` 适配拿不到离线安装器的现场 |
| **健康门禁** | 八项验证门禁可随时重跑；逆序停止保留数据 |
| **离线介质** | 面向离线现场的介质打包与安装，含 demo SSO compose 文件 |
| **可观测套件** | Grafana 看板、vmalert 规则与 file-sd 目标，覆盖 techbase 指标面 |

## 与其他工具的关系

opic-deploy 是**执行层仓库**，不是语义权威：只提供已验证的默认组合，不定义事件、订阅或编排结构。

| 层次 | 相关工具 | 关系 |
|---|---|---|
| 语义权威 | 各能力中心（O-SYS 与 23 个能力中心） | 事件编目、订阅关系、编排结构合法性归能力中心；本仓库的堆栈只承担执行 |
| 应用集成 | [opic-techbase](https://github.com/Project-Opic/opic-techbase) | techbase 不直连 NATS / Temporal 客户端，而是经接口层（`internal/pkg/eventbus`、`internal/pkg/workflow`）调用，其外部实现即本仓库的堆栈 |
| 生产分发 | Temporal Helm Chart、NATS Helm Chart | 本仓库默认内网单节点部署；多节点 + TLS + 外部托管数据库的生产形态用官方 Helm Chart，本仓库配置作为参数取值参考 |
| 镜像仓 | Harbor | 存放后端与前端镜像；第一步安装器默认安装，`--no-registry` 可跳过 |

## 仓库结构

| 组件 | 路径 | 说明 |
|---|---|---|
| **配置源** | [`.env.example`](.env.example) | 唯一配置模板；`bin/gen-env.sh` 生成含全部口令的 `.env` |
| **编排脚本** | [`bin/`](bin) | `common.sh` 公共函数、`gen-env.sh` 口令生成、`install-step1.sh` F0~F8 编排、`verify-step1.sh` 健康门禁、`teardown-step1.sh` 逆序停止、`gen-certs.sh`、`backup-prod.sh` |
| **堆栈** | [`stacks/`](stacks) | `database` / `redis` / `traefik` / `zero-trust` / `casdoor` / `registry`，以及 `nats`（Server + JetStream）与 `temporal`（PG16 + Server + UI + admin-tools） |
| **组件配置** | [`configs/`](configs) | `nats/nats-server.conf`（JetStream 与监听；容量限额写在这里，因为 NATS 配置不支持环境变量插值）与 `temporal/development-sql.yaml` |
| **可观测** | [`observability/`](observability) | Grafana 看板、vmalert 规则、file-sd 目标与安装脚本 |
| **离线介质** | [`offline-kit/`](offline-kit) | 介质打包 / 安装脚本与 demo compose 文件 |
| **文档** | [`docs/`](docs) | 第一步安装与容器化、运维手册、生产方案、O-SYS 集成边界、部署顺序 |

## 基础软件依赖

组件版本锁定在 `.env.example`（均可覆盖），并经生产验证。

| 组件 | 默认版本 | 说明 |
|---|---|---|
| NATS Server | `2.14-alpine` | 2026-08 时点的稳定线（官方最新 2.14.6） |
| Temporal Server | `1.29.0` | auto-setup 镜像上游最高 1.29.x |
| Temporal UI | `2.34.0` | 与 Server 1.29 配套 |
| Temporal admin-tools | `1.30.4` | 上游无 1.29.0；CLI 对 1.29 server 向后兼容 |
| PostgreSQL | `16-alpine` | 与 OPIC 统一 PG16 口径一致 |
| ZITADEL | `v4.19.3` | ghcr tag 带 v 前缀 |
| Harbor | `v2.12.2` | 官方安装器自管；受限网络不可得在线版时用 `HARBOR_INSTALLER_DIR` 离线安装器 |
| Docker Engine | 24+ 与 Compose v2 | 根分区可用空间 ≥ 20 GiB |

升级步骤：改 `.env` 的 tag → `docker compose pull` → `docker compose up -d`（Temporal 的 schema 迁移由 auto-setup 镜像在启动时自动完成）。

## 使用

### 前置

- Docker Engine 24+ 与 Compose v2；根分区可用空间 ≥ 20 GiB
- 端口规划：默认高位端口（DEV 实测 80/443/8080/8000/4222/5432 等常被占用），见 `.env.example` 注释
- 前置网络（脚本自动创建，只需一次）：

```bash
docker network create opic-net
```

### 一键安装第一步·基础设施（推荐）

```bash
bash bin/install-step1.sh                 # F0~F8 全量（含 Harbor）
bash bin/install-step1.sh --no-registry   # 跳过 Harbor（离线拿不到安装器时）
bash bin/verify-step1.sh                  # 八项健康门禁（可随时重跑）
bash bin/teardown-step1.sh                # 逆序停止（数据保留）
```

细节见 [`docs/第一步-容器化部署.md`](docs/第一步-容器化部署.md) 与 [`docs/运维手册-step1.md`](docs/运维手册-step1.md)。

### 逐栈部署 NATS（事件总线）

```bash
cp .env.example .env
vim .env                                  # 至少填 NATS_USER / NATS_PASSWORD

cd stacks/nats
docker compose up -d
bash post-install.sh                      # 校验 JetStream 并打印接入信息

# 已就绪：nats://127.0.0.1:4222 ｜ 监控 http://127.0.0.1:8222/varz
```

### 逐栈部署 Temporal（流程引擎运行）

```bash
vim .env                                  # 再填 TEMPORAL_PG_PASSWORD

cd stacks/temporal
docker compose up -d                      # 首启自动建库表与 schema
bash post-install.sh                      # 等待 SERVING 并创建业务命名空间

# Web UI：http://127.0.0.1:8233 ｜ gRPC：127.0.0.1:7233
```

### 停止 / 清理

```bash
cd stacks/<name>
docker compose down                       # 停容器，保留数据
docker compose down -v                    # 连同匿名卷一并清理（数据目录为 bind mount，需另行删除）
```

## 部署

生产部署遵循 [`docs/部署顺序.md`](docs/部署顺序.md) 的顺序：主机前置 → 数据与身份地基 → 第 3 层中间件 → 23 个能力中心 → 观测收口。**启动正序、停止逆序。**

配置纪律——两条由交付现场事故换来的规则：

1. **只保留真正生效的开关**：任何「配了不生效」的变量都必须删掉——它会在交付现场制造假安全感。
2. **口令只存在于 `.env`**：`configs/` 下的配置文件不含任何口令。NATS 的鉴权经命令行从环境变量注入；Temporal 的库口令经环境变量注入。

> **一个刻意的例外**：NATS 配置不支持环境变量插值，因此 **JetStream 的容量限额写在 `configs/nats/nats-server.conf`**，而不是 `.env`。要调整限额请改该文件——这避免了「改了 .env 却不生效」的悬空配置。

### 安全基线

| 组件 | 默认状态 | 对外暴露前必须做 |
|---|---|---|
| **Temporal** | gRPC frontend（7233）与 Web UI 默认不启用认证（官方默认口径） | 反向代理 + 鉴权，或启用 mTLS / authorization interceptor |
| **NATS** | 已启用 user/password 鉴权（本仓库强制要求 `NATS_PASSWORD`） | 监控端点（8222）不要暴露到公网；跨机部署时启用 TLS |
| **PostgreSQL** | 仅容器网络内可达，未映射宿主端口 | 保持不映射；如需外部访问请走受控代理 |

**部署形态**：本仓库默认按**内网单节点**设计。生产环境需要多节点、TLS、外部托管数据库时，请使用 Temporal 官方 Helm Chart 与 NATS 官方 Helm Chart，本仓库的配置可作为参数取值参考。

## 贡献

提交前请确认：

1. 新堆栈遵循单一配置源纪律：所有参数来自 `.env`，`configs/` 下不含任何口令；
2. 新堆栈附带 `post-install.sh`，校验组件并打印接入信息；
3. 部署顺序或其判据的变更落在 [`docs/部署顺序.md`](docs/部署顺序.md)——本仓单一事实源；
4. 组件版本升级注明验证依据（测了什么、在哪里测的）。

分支与提交信息沿用 `feat|fix|docs|chore(scope): 说明` 格式。

提交贡献即表示同意以[木兰宽松许可证第 2 版](LICENSE)授权该贡献。

## 路线图

本仓库不维护长期功能路线图，计划与进展以下列方式公开：

- **已完成**（近期）：带八项健康门禁与逆序停止的第一步基础设施安装器；NATS 与 Temporal 堆栈的已验证默认组合；面向离线现场的离线介质；techbase 可观测套件。
- **待办**（已知缺口）：多节点生产形态（TLS、外部数据库）刻意交给官方 Helm Chart；其余第 3 层中间件堆栈按同一纪律陆续落地。
- **限制**：本仓库是执行层——不定义事件、订阅或编排结构，语义权威归能力中心。

## 社区

- **问题与建议**：通过仓库 Issue 反馈，附复现步骤与环境信息（组件、版本、部署方式）。
- **内部沟通**：OPIC 平台团队；生产问题走运维值班渠道。

## 安全与支持

- **报告漏洞**：请勿公开提交 Issue，直接联系平台团队。安全基线包括 NATS 强制鉴权、PostgreSQL 不映射宿主端口、口令只存在于 `.env`。
- **支持范围**：当前主分支与生产部署版本。

## 许可证

Copyright © 2026 wjluo

本项目采用**木兰宽松许可证第 2 版（Mulan PSL v2）**，全文见 [`LICENSE`](LICENSE)，也可从 <http://license.coscl.org.cn/MulanPSL2> 获取。

在遵守许可证条款的前提下，你可以自由复制、使用、修改和分发本软件，包括商业使用；分发时需保留版权与许可声明。许可证第 3 条明确不授予商标许可，第 5 条按「现状」提供软件、不附带任何明示或默示担保。

### 第三方组件

本仓库分发的所有组件（NATS、Temporal、PostgreSQL、ZITADEL、Harbor、Traefik 等）均以其上游许可证运行，具体条款以上游项目为准。
