# ==============================================================================
# Harbor 配置模板（v2.12 全键集）—— 由 pre-install.sh 渲染为 harbor.yml
# ==============================================================================
# 口令纪律: HARBOR_ADMIN_PASSWORD / HARBOR_DB_PASSWORD 只存 .env；渲染产物
# harbor-installer/harbor.yml 属运行时文件（.gitignore 已排除）。
# 结构以官方 v2.12 安装器模板为底稿；_version 行由 pre-install 按安装器版本改写。
# ==============================================================================

hostname: __HARBOR_HOSTNAME__

http:
  port: __HARBOR_HTTP_PORT__

# DEV 容器化模式不启用 HTTPS（生产由 O-CRT 证书域供证书后启用 https 段）
# external_url 声明后 UI 与 token 服务按此地址生成链接
external_url: http://__EXTERNAL_URL__

harbor_admin_password: __HARBOR_ADMIN_PASSWORD__

database:
  password: __HARBOR_DB_PASSWORD__
  max_idle_conns: 100
  max_open_conns: 900
  conn_max_lifetime: 5m
  conn_max_idle_time: 0

data_volume: __HARBOR_DATA_DIR__

trivy:
  ignore_unfixed: false
  # 离线/内网环境：不从 GitHub 下载漏洞库（按需手工放 trivy-offline 包）
  skip_update: true
  skip_java_db_update: true
  offline_scan: false
  security_check: vuln
  insecure: false
  timeout: 5m0s

jobservice:
  max_job_workers: 10
  job_loggers:
    - STD_OUTPUT
    - FILE
  logger_sweeper_duration: 1

notification:
  webhook_job_max_retry: 3
  webhook_job_http_client_timeout: 3

log:
  level: info
  local:
    rotate_count: 50
    rotate_size: 200M
    location: /var/log/harbor

_version: __HARBOR_VERSION__
