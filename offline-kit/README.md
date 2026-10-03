# OPIC 离线安装介质包（step1 基础设施 + opic-techbase）

面向**社区运营 / 拓展用户 / DEMO 演示**的单机离线安装介质：无需外网，导入镜像、执行一条脚本，10 分钟内获得一套完整可演示的 OPIC 环境。

## 一、介质包内容

| 组件 | 版本（打包锁定） | 用途 |
|---|---|---|
| PostgreSQL | 16-alpine | 数据面（多库：opicdb/casdoor/zitadel/temporal） |
| Redis | 8.10.2-alpine | 会话吊销等 |
| NATS | 2.14-alpine | 事件总线（JetStream） |
| Temporal | auto-setup 1.29.0 + UI 2.34.0 | 工作流引擎 |
| Casdoor / ZITADEL / ZITADEL-Login | latest / v4.19.3 | 用户/管理员 SSO（可选档） |
| **opic-techbase** 后端 + 前端 | v3.2.0（latest tag） | 技术底座应用本体 |

## 二、制作介质包（源机器，需可访问生产/镜像源）

```bash
cd offline-kit
bash pack.sh v3.2.0        # 产出 opic-offline-kit-v3.2.0.tar.gz + .sha256
```
> 说明：`pack.sh` 会自动从生产 Harbor 给 techbase 镜像打通用别名（`opic/techbase:latest`）。Pigsty 属于生产级数据面安装器（systemd 全家桶），**DEMO 档不含**；社区/演示用介质内 postgres 官方镜像承载多库，生产化时按《技术底座·运维手册》接入 Pigsty。

## 三、目标机安装（离线，一条命令）

要求：Linux x86_64、Docker 已装、磁盘 ≥ 20GB、端口 8081/15432/16379/14222/17233/18088 空闲。

```bash
tar xzf opic-offline-kit-v3.2.0.tar.gz && cd kit
bash install.sh               # core 档：本地登录，完整演示
bash install.sh --with-sso    # 附带 Casdoor/ZITADEL SSO 组件
bash install.sh --check-only  # 仅前置检查
```

脚本自动完成：镜像导入 → 随机口令生成（写入 `.env`）→ 数据库多库初始化 → 服务拉起 → 健康等待 → 输出访问信息。

## 四、安装结果与演示脚本

安装完成输出访问入口与账号（示例）：

```
访问入口:    http://<目标机IP>:8081
默认账号:    admin / admin123（本地登录,带图形验证码）
Temporal UI: http://<目标机IP>:18088
```

**建议演示动线（约 8 分钟）**：
1. 本地登录（展示图形验证码安控）→ 用户工作台
2. 客户申请：新建草稿 → 提交 → 审批中心审批通过（流程留痕）
3. 管理控制台：仪表盘 → 流程设计器（可视化编辑/保存并发布/试运行）
4. AI 智能助理（右下角）：选模型提问；系统工具 → AI 模型配置（多供应商账号管理）
5. 系统工具 → 隔离信息（MCC 中心级隔离边界一览）/ 日志审计 / 系统监控

## 五、开启 SSO（可选）

`--with-sso` 拉起后：
- Casdoor `http://<IP>:18001`（内置 admin/123，请立即改密）；在 Casdoor 建应用并将 techbase 的工作台登录方式切换为 Casdoor（`USER_AUTH_MODE=casdoor` + Casdoor Issuer/ClientId 等 env，见 `configs/casdoor-app.conf.template` 与 techbase 部署指南）；
- ZITADEL `http://<IP>:18080`（首建管理员 `zitadel-admin@zitadel.localhost`，口令见 `.env` 的 `ZITADEL_ADMIN_PASSWORD`）；管理控制台 SSO 按 techbase 部署指南「ZITADEL 接入」注册 OIDC 应用。

## 六、数据与配置

| 位置 | 内容 |
|---|---|
| `.env` | 全部随机口令（务必备份） |
| `runtime/initdb/01-init.sql` | 数据库初始化（首启生成） |
| docker volume `opic-demo_pgdata` / `natsdata` | 业务数据与事件（`docker compose down` 不删除；`down -v` 才清） |

## 七、常见问题

| 问题 | 处理 |
|---|---|
| 端口冲突 | 改 `.env` 对应 `_PORT` 后重新 `install.sh`（或 `docker compose up -d`） |
| 镜像导入失败 | 确认 images/ 目录完整（对照 `.sha256`） |
| 前端打不开 | `docker logs opic-demo-frontend`；确认 8081 未被占用 |
| 想重置全部数据 | `docker compose -p opic-demo -f docker-compose.demo.yml down -v && rm -rf runtime/initdb && bash install.sh` |

## 八、从 DEMO 到生产

DEMO 档为**单机单实例演示形态**。生产部署差异：
1. 数据面替换为 Pigsty（PG 高可用 + 监控，见《技术底座·运维手册》）；
2. 入口换成 Traefik + 泛域名 https（`*.opic-ai.ccoe.tech`）+ 正式证书；
3. SSO 按生产手册完整对接（ZITADEL Login 组件 / 应用注册 / 角色映射）；
4. 镜像走 Harbor 私仓（`make deploy-prod` 流水线）。
