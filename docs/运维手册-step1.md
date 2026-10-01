# 第一步·基础设施运维手册（step1 Ops Manual）

| 项 | 值 |
|---|---|
| 适用范围 | opic-deploy 第一步 8 项基础设施（容器化模式，DEV/单机形态） |
| 版本 | v1.0 · 2026-10-01 |
| 部署指南 | [`第一步-容器化部署.md`](第一步-容器化部署.md) |
| 纪律来源 | 115 号 §6.3 启停纪律（启动正序、停止逆序、回滚优先 `down` 非 `down -v`） |

---

## 一、日常启停

```bash
cd /opt/opic-deploy-step1

# 启动（正序，幂等）
bash bin/install-step1.sh

# 停止（逆序，数据保留）
bash bin/teardown-step1.sh

# 停止并删除数据（⚠ 破坏性，需输入 PURGE 确认；.env 保留）
bash bin/teardown-step1.sh --purge
```

单栈操作（不破坏顺序语义时）：

```bash
cd stacks/<name> && docker compose ps|logs -f|restart|up -d|down
```

## 二、健康检查

一键八项门禁（可进 crontab 巡检）：

```bash
bash bin/verify-step1.sh        # 全绿退出码 0
```

逐组件手工探针：

| 组件 | 命令 |
|---|---|
| PostgreSQL | `docker exec opic-pg pg_isready -U postgres` |
| Redis | `docker exec opic-redis redis-cli --no-auth-warning -a "$REDIS_PASSWORD" ping` |
| Traefik | `curl -s http://127.0.0.1:18880/ping` |
| ZITADEL | `curl -s -H "Host: auth.192.168.3.200.nip.io" http://127.0.0.1:18880/debug/healthz` |
| Casdoor | `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18000/` |
| NATS | `curl -s http://127.0.0.1:8222/healthz` |
| Temporal | `docker run --rm --network opic-net --entrypoint temporal temporalio/admin-tools:1.30.4 operator cluster health --address temporal:7233` |
| Harbor | `curl -s http://127.0.0.1:18700/api/v2.0/health` |

## 三、凭据与密钥管理

- **唯一口令源是 `/opt/opic-deploy-step1/.env`**（权限 600）。丢失即失去全部凭据。
- **`ZITADEL_MASTERKEY`（32 字符）是最高优先级密钥**：ZITADEL 用它加密库内全部密钥材料，丢失 = ZITADEL 既有数据不可用。备份要求：`.env` 加密存放（如 `age`/`gpg`），至少一份异地。
- 改口令流程：改 `.env` → `docker compose up -d`（重建受影响容器）。**ZITADEL masterkey 不可换**（换了等于销毁数据）；应用口令（PG/Redis/NATS 等）在容器重建后即生效，PG 已建角色的口令需同步 `ALTER ROLE`。

## 四、备份与恢复

| 对象 | 备份 | 恢复 |
|---|---|---|
| PostgreSQL（全部库） | `docker exec opic-pg pg_dumpall -U postgres \| gzip > /backup/pg-$(date +%F).sql.gz` | `gunzip -c <file> \| docker exec -i opic-pg psql -U postgres` |
| Redis | `docker exec opic-redis redis-cli --no-auth-warning -a "$REDIS_PASSWORD" BGSAVE` 后拷 `/opt/opic/redis/data/appendonlydir/` | 停栈 → 拷回数据目录 → 起栈 |
| ZITADEL | `.env`（masterkey）+ 上面的 PG 备份（含 zitadel 库） | 两者配对恢复，缺一不可 |
| NATS JetStream | 拷 `/opt/opic/nats/data/jetstream/`（建议先停 nats 容器保证一致） | 停栈 → 拷回 → 起栈 |
| Temporal | PG 备份（含 temporal/temporal_visibility） | 随 PG 恢复 |
| Harbor | 拷 `/opt/opic/harbor/data/`（含 registry 数据与 harbor DB，建议停机冷备） | 停 harbor → 拷回 → 起 harbor |

建议最小巡检 cron（示例，每天 02:00 备份 + 每小时探针）：

```cron
0 2 * * * docker exec opic-pg pg_dumpall -U postgres | gzip > /backup/pg-$(date +\%F).sql.gz
0 * * * * /opt/opic-deploy-step1/bin/verify-step1.sh || echo "step1 门禁异常" | wall
```

## 五、升级与回滚

```bash
# 升级某组件：改 .env 的 *_IMAGE_TAG → 拉新镜像 → 逆序停 → 正序起
vim .env                                    # 如 TRAEFIK_IMAGE_TAG=v3.7.13
cd stacks/traefik && docker compose pull
cd ../.. && bash bin/teardown-step1.sh && bash bin/install-step1.sh
```

- **ZITADEL 升级**：小版本直接升；跨大版本先读官方迁移公告（schema 由其自管）。
- **回滚**：`.env` 改回旧 tag 后同样流程；数据目录不删（bind mount），旧版本可直接挂回。
- **不要 `down -v`**：它只清匿名卷、清不掉 bind mount 数据，但会误删 ZITADEL bootstrap 卷等具名卷。

## 六、监控与日志

| 端点 | 用途 |
|---|---|
| Traefik dashboard `:18887/dashboard/` | 路由/中间件/后端健康 |
| Traefik API `:18887/api/http/routers` | 程序化巡检路由注册 |
| NATS `:8222/varz`、`/jsz`、`/connz` | 运行指标、JetStream、连接 |
| Temporal UI `:8233` | 工作流执行历史 |
| Harbor `/api/v2.0/health`、`/api/v2.0/systeminfo` | 仓库健康 |
| `docker compose logs -f <svc>`（各栈目录） | 逐栈日志；Traefik 开启了 accesslog |

## 七、安全基线（对外/上生产前必须逐项核对）

1. Casdoor `admin/123` **首登改密**；ZITADEL admin 口令确认已按复杂度设置并轮换。
2. Traefik 关闭 `api.insecure`（dashboard 走受控路由+鉴权）。
3. Temporal gRPC/UI 默认**无认证**——只允许内网，对外必须经网关加认证（或启用 mTLS）。
4. NATS monitor 8222 不暴露公网；跨机时客户端与监控启用 TLS。
5. PG/Redis 回环排障口（15432/26379）只在本机使用；生产建议注释 compose 的 `ports` 段。
6. `.env` 600 且不进 git；`.env` 备份加密。
7. Traefik 发现约束 `opic.stack` 标签必须保留——否则会收编宿主上其他项目的 traefik 路由（实测教训，见部署指南 §六）。

## 八、故障排查速查

| 症状 | 排查 | 处置 |
|---|---|---|
| 容器反复重启 | `docker logs <container> --tail 50` | 按日志对号 §九/部署指南 §六 |
| `port is already allocated` | `ss -tlnp \| grep <port>` 找占用容器 | `.env` 换端口（DEV 常见：80/443/8080/8000/4222/5432/16379 均被占） |
| 镜像拉取超时/白名单 | 换镜像源：docker hub tag 不带 `v`、ghcr tag 带 `v`；或 mirror 前缀直拉后 `docker tag` | ZITADEL 用 `ghcr.io/zitadel/zitadel:v4.x` |
| ZITADEL setup 报 `PasswordComplexityPolicy` | 口令缺大写/符号 | `.env` 换 `Op1-` 前缀口令，重置库（见下）重装 |
| ZITADEL 经网关 404/instance not found | Host 头与 `ZITADEL_DOMAIN` 不一致 | curl 加 `-H "Host: $ZITADEL_DOMAIN"`；浏览器走 nip.io 域名 |
| nip.io 解析不了（内网无外网 DNS） | `nslookup auth.192.168.3.200.nip.io` | 访问机 `/etc/hosts` 加 `192.168.3.200 auth.192.168.3.200.nip.io` |
| Harbor 安装器下载失败 | `packages/` 放离线 tgz 后重跑 `stacks/registry/pre-install.sh` | 离线包地址见 harbor releases |
| Traefik 路由缺失 | dashboard 查 routers；确认目标容器带 `opic.stack` 标签且 `traefik.enable=true` | 补标签 |
| 磁盘 >90% | `docker system df`、`du -sh /opt/opic/*` | `docker image prune -f`；清旧镜像 tag |

**ZITADEL 数据重置（仅 DEV，破坏性；`down -v` 与任何栈目录操作前必须先 `set -a; source ../../.env; set +a`，compose 对 down/ps 也要插值）**：

```bash
cd stacks/zero-trust && docker compose down && cd ../..
docker exec opic-pg psql -U postgres -c "DROP DATABASE IF EXISTS zitadel WITH (FORCE);" \
  -c "CREATE DATABASE zitadel OWNER zitadel;"
cd stacks/zero-trust && docker compose up -d && bash post-install.sh
```

## 九、历史实测问题台账（2026-10-01 DEV 192.168.3.200）

| # | 症状 | 根因 | 修复 |
|:--:|---|---|---|
| 1 | redis compose 校验失败 `additional properties 'environment'` | healthcheck 段不支持 environment 键 | 移到 service 级 environment，healthcheck 用 `redis-cli ping` |
| 2 | redis 启动报 0.0.0.0:16379 已分配 | 空值端口变量绑随机口 + 宿主 oc-redis 占 16379 | compose 固定回环默认端口，DEV 换 26379 |
| 3 | traefik 判 unhealthy（404） | scratch 镜像 healthcheck CLI 默认探 8080，ping 在 web:80 | healthcheck 显式传 `--ping.entrypoint=web --entrypoints.web.address=:80` |
| 4 | traefik 收编 go-admin-kit 路由 | 共享 docker.sock + 对方容器有 traefik labels | `providers.docker.constraints=LabelRegex(\`opic.stack\`,\`.+\`)` |
| 5 | zitadel/zitadel-login 拉取失败 | hub 镜像不在 mirror 白名单；tag 前缀 hub 无 v / ghcr 带 v | 改 ghcr.io + `v4.19.3` |
| 6 | zitadel 首启 setup 失败 `PasswordComplexityPolicy.HasUpper` | 生成口令纯小写 hex 不满足复杂度策略 | gen-env 口令改 `Op1-` 前缀（大写+小写+数字+符号） |
| 7 | zitadel 反复重启 `login-client.pat: permission denied` | 命名卷 root 属主 × 镜像 uid 1000，且镜像内无该目录可继承 | 栈内加一次性 `init-perms` 容器 chown 卷 |
| 8 | login 经网关 502（healthz 正常） | login 路由 label 挂在了 API 容器上 | Traefik service 只指向 label 所在容器 → 路由迁到 login 容器 |
| 9 | traefik 路由始终不注册 | traefik 过滤非 healthy 容器 × `zitadel ready` 拨测经网关外部域名 = 死锁 | zitadel 不设 healthcheck，门禁交给 post-install |
| 10 | casdoor panic `zero-length delimited identifier` | `dbName` 只从 app.conf 读 | app.conf 补 `dbName = casdoor` |
| 11 | casdoor panic `permission denied to create database` | `--createDatabase` 需 CREATEDB；库已存在 | 去掉该参数，建表由 orm 自理 |
| 12 | nats `unknown field "max_streams"` | 该限额是账号级配置 | 从服务器配置移除 |
| 13 | temporalio/auto-setup:1.30.4 全源 manifest unknown | 上游 docker-compose 仓已归档，无 1.30+ 镜像 | 全仓统一 1.29.0（受限网络经代理机 `docker save`/`load` 迁移；admin-tools 用 1.30.4，CLI 对 1.29 server 向后兼容） |
| 14 | harbor prepare `KeyError: max_job_workers` | 手写精简模板缺 v2.12 必需键集 | 模板改为官方 v2.12 全键集（harbor.yml.tpl） |
