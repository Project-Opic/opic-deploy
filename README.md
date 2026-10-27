# opic-deploy

> 简体中文: [README-zh.md](README-zh.md)

[![License](https://img.shields.io/badge/License-MulanPSL--2.0-2E7D32)](LICENSE)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)](stacks/nats/docker-compose.yml)
[![NATS](https://img.shields.io/badge/NATS-2.14-27AAE1)](stacks/nats)
[![Temporal](https://img.shields.io/badge/Temporal-1.29-6E56CF)](stacks/temporal)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-4169E1?logo=postgresql&logoColor=white)](stacks/database)

[Documentation](#documentation) | [Architecture](#architecture) | [Usage](#usage) | [Deployment](#deployment) | [Roadmap](#roadmap) | [License](#license)

**opic-deploy is the unified deployment and operations repository for the OPIC open intelligent compute platform**: one `.env` configuration source, one `stacks/<name>/` per component, and one offline media kit. Stacks interconnect through the external Docker network `opic-net`, and every component takes its parameters from the single configuration source — no second source of truth.

The repository answers a recurring delivery question: how do you bring up a distributed platform on-site without configuration drift? Ports, passwords, and data directories are converged into one file; semantic authority (event catalogs, subscription relations, orchestration-structure validity) stays in the capability centers, while this repository only ships the verified default combinations of the layer-3 executors.

This repository contains the step-1 infrastructure installer with health gates, per-component Docker Compose stacks, pinned component versions, an observability bundle, an offline kit, and the deployment-order specification.

## Documentation

| Document | Contents |
|---|---|
| [第一步·基础设施安装](docs/第一步-基础设施安装.md) | Step-1 infrastructure installation walkthrough |
| [第一步·容器化部署](docs/第一步-容器化部署.md) | Containerized deployment of step 1 |
| [运维手册 step1](docs/运维手册-step1.md) | Operations manual for step 1 |
| [生产部署方案](docs/生产部署方案.md) | Production deployment plan |
| [O-SYS 集成说明](docs/O-SYS-集成说明.md) | Semantic correspondence with capability centers and the four hard boundaries |
| [部署顺序](docs/部署顺序.md) | Deployment order, the J1~J7 ordering criteria, and per-item rationale — the single source of truth |
| [techbase-ops](docs/techbase-ops.md) | Techbase operations notes |

## Architecture

opic-deploy is organized as **one configuration source + layered stacks + offline media**:

- **`.env`** — the single configuration source. `bin/gen-env.sh` generates it with complexity-compliant passwords; every compose file and script reads from it and nowhere else.
- **`stacks/<name>/`** — one stack per component, each with a `docker-compose.yml` and an optional `post-install.sh` that verifies the component and prints its access information.
- **`bin/`** — the orchestration layer: `install-step1.sh` (F0~F8, idempotent), `verify-step1.sh` (eight health gates, re-runnable at any time), `teardown-step1.sh` (reverse-order stop, data retained), plus `gen-certs.sh` and `backup-prod.sh` for production operations.
- **`observability/`** — the techbase observability bundle: Grafana dashboard, vmalert rules, file-based service discovery, and an installer.
- **`offline-kit/`** — the offline media kit: `pack.sh` builds it, `install.sh` consumes it, with demo compose files for air-gapped sites.

Deployment paths:

- Step 1 (recommended): `bash bin/install-step1.sh` brings up the infrastructure in order — host prerequisites → data and identity foundation → layer-3 middleware → observability.
- Per stack: `cp .env.example .env && vim .env`, then `cd stacks/<name> && docker compose up -d && bash post-install.sh`.
- Start in order, stop in reverse order — the full order, the seven J1~J7 criteria, and the per-item rationale live in [`docs/部署顺序.md`](docs/部署顺序.md).

Semantics: the components here are **executors only**. Event catalogs, subscription relations, and orchestration-structure validity remain the semantic authority of the capability centers (see [`docs/O-SYS-集成说明.md`](docs/O-SYS-集成说明.md)).

### Core Capabilities

| Capability | What it does |
|---|---|
| **Event bus stack** | NATS Server + JetStream with enforced user/password authentication, verified by `post-install.sh` (client `4222`, monitoring `8222`) |
| **Workflow runtime stack** | Temporal Server + PostgreSQL 16 + Web UI + admin-tools, with automatic schema setup and the business namespace created on first start (gRPC `7233`, UI `8233`) |
| **Infrastructure stacks** | Database, Redis, Traefik, zero-trust (ZITADEL), Casdoor, and registry (Harbor) stacks sharing the same configuration discipline |
| **Step-1 installer** | F0~F8 one-command orchestration (idempotent), with `--no-registry` for sites without the offline installer |
| **Health gates** | Eight verification gates re-runnable at any time, plus reverse-order teardown that retains data |
| **Offline kit** | Media packing and installation for air-gapped delivery, including demo SSO compose files |
| **Observability bundle** | Grafana dashboard, vmalert rules, and file-sd targets for the techbase metrics surface |

## How opic-deploy Relates to Other Tools

opic-deploy is an **execution-layer repository**, not a semantic authority. It ships verified default combinations; it does not define events, subscriptions, or orchestration structures.

| Layer | Tools | Relationship |
|---|---|---|
| Semantic authority | Capability centers (O-SYS and the 23 centers) | Event catalogs, subscription relations, and orchestration-structure validity belong to the centers; the stacks here only execute |
| Application integration | [opic-techbase](https://github.com/Project-Opic/opic-techbase) | The techbase must not connect NATS / Temporal clients directly; it calls through the interface layer (`internal/pkg/eventbus`, `internal/pkg/workflow`) whose external implementations are the stacks in this repository |
| Production distribution | Temporal Helm Chart, NATS Helm Chart | This repository defaults to single-node intranet deployments; for multi-node production with TLS and external databases, use the official Helm charts — this repository's configuration serves as the parameter reference |
| Registry | Harbor | Stores backend and frontend images; the step-1 installer provisions it unless `--no-registry` is passed |

## Repository Map

| Component | Path | Description |
|---|---|---|
| **Configuration source** | [`.env.example`](.env.example) | The single configuration template; `bin/gen-env.sh` generates `.env` with all passwords |
| **Orchestration scripts** | [`bin/`](bin) | `common.sh` shared functions, `gen-env.sh` password generation, `install-step1.sh` F0~F8 orchestration, `verify-step1.sh` health gates, `teardown-step1.sh` reverse-order stop, `gen-certs.sh`, `backup-prod.sh` |
| **Stacks** | [`stacks/`](stacks) | `database` / `redis` / `traefik` / `zero-trust` / `casdoor` / `registry` plus `nats` (Server + JetStream) and `temporal` (PG16 + Server + UI + admin-tools) |
| **Component configs** | [`configs/`](configs) | `nats/nats-server.conf` (JetStream and listeners; capacity limits live here because NATS configs do not interpolate environment variables) and `temporal/development-sql.yaml` |
| **Observability** | [`observability/`](observability) | Grafana dashboard, vmalert rules, file-sd targets, installer |
| **Offline kit** | [`offline-kit/`](offline-kit) | Media pack / install scripts and demo compose files |
| **Documentation** | [`docs/`](docs) | Step-1 installation and containerization, operations manual, production plan, O-SYS integration boundary, deployment order |

## Base Software

Component versions are pinned in `.env.example` (all overridable) and verified in production.

| Component | Default version | Notes |
|---|---|---|
| NATS Server | `2.14-alpine` | Stable line as of 2026-08 (upstream latest 2.14.6) |
| Temporal Server | `1.29.0` | Highest 1.29.x from the auto-setup image |
| Temporal UI | `2.34.0` | Pairs with Server 1.29 |
| Temporal admin-tools | `1.30.4` | Upstream has no 1.29.0; the CLI is backward compatible with the 1.29 server |
| PostgreSQL | `16-alpine` | Aligned with the platform-wide PG16 standard |
| ZITADEL | `v4.19.3` | ghcr tag carries the `v` prefix |
| Harbor | `v2.12.2` | Official installer self-managed; use `HARBOR_INSTALLER_DIR` for the offline installer when the restricted network cannot reach v2.15.2 |
| Docker Engine | 24+ with Compose v2 | Root filesystem with ≥ 20 GiB free |

Upgrade path: change the tag in `.env` → `docker compose pull` → `docker compose up -d`. The Temporal schema migration runs automatically at container start via the auto-setup image.

## Usage

### Prerequisites

- Docker Engine 24+ and Compose v2; root filesystem with ≥ 20 GiB free
- Port planning: default high ports (80/443/8080/8000/4222/5432 are frequently occupied in DEV — see the `.env.example` comments)
- The shared external network, created once by the scripts:

```bash
docker network create opic-net
```

### One-Command Step 1 · Infrastructure (recommended)

```bash
bash bin/install-step1.sh                 # F0~F8 full run (including Harbor)
bash bin/install-step1.sh --no-registry   # skip Harbor (when the offline installer is unavailable)
bash bin/verify-step1.sh                  # eight health gates (re-runnable at any time)
bash bin/teardown-step1.sh                # reverse-order stop (data retained)
```

Details: [`docs/第一步-容器化部署.md`](docs/第一步-容器化部署.md) and [`docs/运维手册-step1.md`](docs/运维手册-step1.md).

### Per-Stack Deployment — NATS (event bus)

```bash
cp .env.example .env
vim .env                                  # at minimum NATS_USER / NATS_PASSWORD

cd stacks/nats
docker compose up -d
bash post-install.sh                      # verifies JetStream and prints access information

# ready: nats://127.0.0.1:4222 ｜ monitoring http://127.0.0.1:8222/varz
```

### Per-Stack Deployment — Temporal (workflow runtime)

```bash
vim .env                                  # also TEMPORAL_PG_PASSWORD

cd stacks/temporal
docker compose up -d                      # schema setup on first start
bash post-install.sh                      # waits for SERVING and creates the business namespace

# Web UI: http://127.0.0.1:8233 ｜ gRPC: 127.0.0.1:7233
```

### Stop / Clean Up

```bash
cd stacks/<name>
docker compose down                       # stop containers, retain data
docker compose down -v                    # also remove anonymous volumes (data directories are bind mounts and must be deleted separately)
```

## Deployment

Production deployment follows the order in [`docs/部署顺序.md`](docs/部署顺序.md): host prerequisites → data and identity foundation → layer-3 middleware → the 23 capability centers → observability. **Start in order, stop in reverse order.**

Configuration discipline — two rules that exist because of delivery-site incidents:

1. **Only switches that actually take effect are kept.** Any variable that is configured but has no effect must be deleted — it manufactures false confidence on site.
2. **Passwords exist only in `.env`.** Files under `configs/` contain no passwords. NATS authentication is injected from environment variables via the command line; Temporal's database password is injected the same way.

> **One deliberate exception**: NATS configuration does not support environment-variable interpolation, so the **JetStream capacity limits live in `configs/nats/nats-server.conf`**, not in `.env`. Adjust limits there — this avoids a dangling configuration where changing `.env` has no effect.

### Security Baseline

| Component | Default state | Required before external exposure |
|---|---|---|
| **Temporal** | gRPC frontend (7233) and Web UI have **no authentication by default** (official default) | Reverse proxy with authentication, or enable mTLS / authorization interceptor |
| **NATS** | User/password authentication enabled (this repository requires `NATS_PASSWORD`) | Do not expose the monitoring endpoint (8222) to the public internet; enable TLS for cross-host deployments |
| **PostgreSQL** | Reachable only inside the container network; **no host port mapped** | Keep it unmapped; use a controlled proxy for external access |

**Deployment shape**: this repository defaults to a **single-node intranet** design. For multi-node production, TLS, or externally managed databases, use the official Temporal and NATS Helm charts; this repository's configuration serves as the parameter reference.

## Contributing

Before opening a pull request, please confirm:

1. New stacks follow the single-configuration-source discipline: every parameter comes from `.env`, and no password is written into `configs/`.
2. Any new stack ships with a `post-install.sh` that verifies the component and prints its access information.
3. Changes to the deployment order or its criteria land in [`docs/部署顺序.md`](docs/部署顺序.md) — this repository's single source of truth for ordering.
4. Component version bumps state the verification basis (what was tested, where).

Branch names and commit messages follow `feat|fix|docs|chore(scope): summary`.

By submitting a contribution, you agree to license it under the [Mulan PSL v2](LICENSE).

## Roadmap

This repository does not maintain a long-range feature roadmap. Planned work and progress are tracked in the open:

- **Recently completed**: the step-1 infrastructure installer with eight health gates and reverse-order teardown; the NATS and Temporal stacks with verified default combinations; the offline kit for air-gapped sites; the techbase observability bundle.
- **Known gaps**: multi-node production topologies (TLS, external databases) are intentionally delegated to the official Helm charts; remaining layer-3 middleware stacks follow the same discipline as they land.
- **Limitations**: this repository is an execution layer — it defines no events, subscriptions, or orchestration structures; semantic authority stays with the capability centers.

## Community

- **Issues and suggestions**: open a repository issue with reproduction steps and environment details (component, version, deployment mode).
- **Internal channels**: the OPIC platform team; production incidents go through the on-call channel.

## Security & Support

- **Reporting a vulnerability**: please do not open a public issue; contact the platform team directly. The security baseline includes enforced NATS authentication, PostgreSQL without host port mapping, and passwords confined to `.env`.
- **Support scope**: the current main branch and the deployed production version.

## License

Copyright © 2026 wjluo

This project is licensed under the **Mulan Permissive Software License, Version 2 (Mulan PSL v2)**. The full text is in [`LICENSE`](LICENSE) and is also available at <http://license.coscl.org.cn/MulanPSL2>.

Subject to the terms of the license, you may copy, use, modify, and distribute this software, including for commercial purposes; copyright and license notices must be retained when redistributing. Section 3 grants no trademark license, and Section 5 provides the software on an "AS IS" basis without warranties of any kind.

### Third-Party Components

All components shipped by this repository (NATS, Temporal, PostgreSQL, ZITADEL, Harbor, Traefik, and others) run under their respective upstream licenses. Refer to each upstream project for the exact terms.
