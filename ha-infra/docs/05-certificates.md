# 05 · 证书管理

## PKI 架构

| 层 | CA | 签发工具 | 用途 |
|---|---|---|---|
| 平台 CA | 133 /opt/cfssl-platform/ca/ | cfssl 1.7.1 | Harbor TLS / etcd TLS / client |
| Pigsty 内部 CA | 141 容器 /data/pigsty/ca/ | Pigsty ca role | node/etcd/pg/minio 内部 |
| Kafka TLS | /etc/kafka/ssl/truststore.p12 | JDK keytool | Kafka broker/inter-broker SSL |

## 规则

- **133 平台 CA 的 `ca-key.pem` 不出 133**
- 签发产物经 `/dev/shm/opic-ha-sign`（tmpfs 0700）分发，用后 `shred -u`
- cfssl 1.7.1 的 `gencert` 无 `-use- CSR` 分支——不能签别的机器的 CSR（§二-26）

## Harbor 服务证书

### 查看当前证书

```bash
openssl x509 -noout -subject -serial -dates -fingerprint \
  /opt/opic/harbor/tls/opic-harbor.pem
```

### 重新签发

```bash
# 1. 编辑 CSR 模板（SAN 含通配+VIP+三 IP）
cd /opt/opic/cfssl/csr/
vim opic-harbor-server-csr.json

# 2. 签发
cd /opt/opic/cfssl
./sign-all-certs.sh

# 3. 分发（133 直接落 /opt/opic/harbor/tls/）
# 134/141 经 ssh stdin 管道传（不落本机磁盘）

# 4. 重启 Harbor
cd /opt/opic/ha-stack/harbor-installer && docker compose restart
```

## etcd 证书

```bash
# 签发
cfssl gencert \
  -ca /opt/cfssl-platform/ca/ca.pem \
  -ca-key /opt/cfssl-platform/ca/ca-key.pem \
  -config /opt/opic/cfssl/opic-ca-config.json \
  -profile server \
  csr/etcd-133-server-csr.json | cfssljson -bare /tmp/etcd-133

# 分发（stdin 管道 → 目标节点）
# 重启 etcd 容器
```

## CA 确权（§二-27 教训）

**⚠ 2026-10-09 17:30 站点侧整体换发过 CA**——`sign.sh` 第一行就是 `-initca`，跑一次就重新生成 CA 私钥并重签全部历史件（不可逆）。

**只用自己写的 `issue-cert.sh`**，绝不执行 `sign.sh`。

## 证书有效期

| 证书 | 有效期 | 到期时间 |
|------|--------|----------|
| 平台 CA | 100 年（876000h） | 2126-09-15 |
| Harbor server | ~100 年 | 2126-09-15 |
| etcd server ×3 | ~100 年 | 2126-09-15 |
| client 证书 | ~100 年 | 2126-09-15 |

> 有效期 100 年（876000h）= 2026-10-09 按平台现值对齐。
