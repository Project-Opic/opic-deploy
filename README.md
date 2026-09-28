# opic-deploy — OPIC 平台部署工程

OPIC 智算平台的统一部署与运维仓库。采用 **单一配置文件 ＋ 分层 stack ＋ 离线介质** 的组织方式：一个 `.env` 配置源，每个组件一个 `stacks/<name>/`，堆栈之间通过外部 Docker 网络 `opic-net` 互联。

**当前包含的 stack**

| Stack | 组件 | 在 OPIC 本体体系中的位置 |
|---|---|---|
| [`nats`](stacks/nats/) | NATS Server ＋ JetStream | `O-SYS` **事件总线**的第 3 层可替换实现 |
| [`temporal`](stacks/temporal/) | Temporal Server ＋ PostgreSQL 16 ＋ Web UI | `O-SYS` **流程引擎运行 / 工作流编排运行时**的第 3 层可替换实现 |

> **两者的归属与边界见 [`docs/O-SYS-集成说明.md`](docs/O-SYS-集成说明.md)** —— 落 stack 之前请先读它：组件只承担**执行器**职责，事件编目、订阅关系、编排结构合法性等**语义权威仍在能力中心**。
>
> **部署顺序见 [`docs/部署顺序.md`](docs/部署顺序.md)** —— 覆盖「主机前置 → 数据与身份地基 → 第 3 层中间件 → 23 个能力中心 → 观测收口」的完整顺序、7 条排序判据（J1~J7）与逐条专家理由。**启动正序、停止逆序**。

---

## 一、这个仓库解决什么问题

引入 NATS 与 Temporal 后，分布式能力对交付提出了三个新要求：

- **配置要收敛**：端口、口令、数据目录若散落在各 stack 的 compose 里，改一次现场参数要改十几处。
- **语义不能漂移**：这两个组件是「第 3 层实现」，一旦有第二处定义事件或工作流，就产生了第二份真相。
- **现场要能起得来**：Temporal 的持久化、可见性存储、健康检查都有坑，需要一个已验证的默认组合。

本仓库把上述内容收敛为：**一个 `.env` ＋ 每个组件一个 stack ＋ 一份集成边界说明**。

---

## 二、快速开始

### 前置

- Docker Engine 24+ 与 Compose v2
- Temporal 全栈（PG ＋ Server ＋ UI）建议预留 **4 GB 内存**；NATS 极轻量（容器约 30 MB 镜像）
- 前置网络（只需一次）：

```bash
docker network create opic-net
```

### ① 部署 NATS（事件总线）

```bash
cp .env.example .env
vim .env                                  # 至少填 NATS_USER / NATS_PASSWORD

cd stacks/nats
docker compose up -d
bash post-install.sh                      # 校验 JetStream 并打印接入信息

# 已就绪：nats://127.0.0.1:4222 ｜ 监控 http://127.0.0.1:8222/varz
```

### ② 部署 Temporal（流程引擎运行）

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

---

## 三、目录结构

```
opic-deploy/
├── .env.example                       # 唯一配置源模板（→ 复制为 .env）
├── stacks/
│   ├── nats/
│   │   ├── docker-compose.yml         # NATS Server ＋ JetStream
│   │   └── post-install.sh            # 校验 JetStream ＋ 输出接入信息
│   └── temporal/
│       ├── docker-compose.yml         # PG16 ＋ Temporal ＋ UI ＋ admin-tools(profile)
│       └── post-install.sh            # 等 SERVING ＋ 建业务命名空间
├── configs/
│   ├── nats/nats-server.conf          # JetStream 与监听配置
│   └── temporal/development-sql.yaml  # Temporal 动态配置
└── docs/
    ├── O-SYS-集成说明.md               # 与能力中心的语义对应与四条硬边界
    └── 部署顺序.md                     # 部署顺序、排序判据（J1~J7）与专家理由 —— 本仓单一事实源
```

---

## 四、配置说明

全部可调项集中在 **`.env`**（见 `.env.example` 的逐项注释）。两条纪律：

1. **只保留真正生效的开关**：任何「配了不生效」的变量都必须删掉——它会在交付现场制造假安全感。
2. **口令只存在于 `.env`**：`configs/` 下的配置文件**不含**任何口令。NATS 的鉴权经命令行从环境变量注入；Temporal 的库口令经环境变量注入。

> **一个例外**：NATS 配置不支持环境变量插值，因此 **JetStream 的容量限额写在 `configs/nats/nats-server.conf`**，而不是 `.env`。要调整限额请改该文件（这是刻意的设计，避免出现"改了 .env 却不生效"的悬空配置）。

---

## 五、安全须知

| 组件 | 默认状态 | 对外暴露前必须做 |
|---|---|---|
| **Temporal** | gRPC frontend（7233）与 Web UI **默认不启用认证**（官方默认口径） | 反向代理 ＋ 鉴权，或启用 mTLS / authorization interceptor |
| **NATS** | 已启用 user/password 鉴权（本仓库强制要求 `NATS_PASSWORD`） | 监控端点（8222）**不要暴露到公网**；跨机部署时启用 TLS |
| **PostgreSQL** | 仅容器网络内可达，**未映射宿主端口** | 保持不映射；如需外部访问请走受控代理 |

**部署形态建议**：本仓库默认按**内网单节点**设计。生产环境需要多节点、TLS、外部托管数据库时，请使用 Temporal 官方 Helm Chart 与 NATS 官方 Helm Chart，本仓库的配置可作为参数取值参考。

---

## 六、版本

| 组件 | 默认版本 | 说明 |
|---|---|---|
| NATS Server | `2.14-alpine` | 2026-08 时点的稳定线（官方最新 2.14.6） |
| Temporal Server | `1.30.4` | 2026-08 时点稳定版 |
| Temporal UI | `2.34.0` | 与 Server 1.30 配套 |
| PostgreSQL | `16-alpine` | 与 OPIC 统一 PG16 口径一致 |

版本均可经 `.env` 覆盖。升级步骤：改 `.env` 的 tag → `docker compose pull` → `docker compose up -d`（Temporal 的 schema 迁移由 auto-setup 镜像在启动时自动完成）。

---

## 七、与 opic-techbase 的对接

`opic-techbase`（OPIC 平台底座项目）**不应直连** NATS / Temporal 客户端，而应经接口层调用：

| 能力 | 接口层 | 默认实现 | 外部实现 |
|---|---|---|---|
| 事件发布 / 订阅 | `internal/pkg/eventbus` | 进程内（零依赖） | NATS（本仓库 `stacks/nats`） |
| 工作流执行 | `internal/pkg/workflow` | 自研轻量引擎 | Temporal（本仓库 `stacks/temporal`） |

接口层的意义：保持脚手架「复制即可运行」的轻量特性，并让中间件不可用时业务系统仍可降级 —— 这与「第 3 层可替换」纪律一致。

---

## 八、参考出处

| 项 | 出处 |
|---|---|
| 语义级 / 实现级判据、执行器不建对象 | 《00-总体规划-OPIC本体化重构》附录 A；`O-SYS` 正文 §1.3 |
| 归属与承接登记 | 总纲附录 **A.2 v3.3 增补映射**；`O-SYS` 编制说明 **G.2** |
| 归属评估过程 | `opic-ontology/output/112-评估-Temporal与NATS归属及techbase更新.md` |
| Temporal 部署形态与认证默认值 | Temporal 官方文档与 `temporalio/docker-compose` 仓库（2026-08 核对） |
| NATS JetStream 投递语义 | NATS 官方文档 `nats-concepts/jetstream`（at-least-once 为基础保证） |
