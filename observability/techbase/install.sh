#!/bin/bash
# techbase 可观测接入 Pigsty 监控栈（VictoriaMetrics 全家桶）——在监控宿主(192.168.3.200)执行。
# 用法: bash install.sh   （幂等）
set -e
# 1) vmetrics 抓取目标(file_sd)
mkdir -p /infra/targets/techbase
cp file-sd-techbase.yml /infra/targets/techbase/techbase.yml
if ! grep -q "job_name: techbase" /infra/prometheus.yml; then
cat >> /infra/prometheus.yml << 'YML'
  #--------------------------------------------------------------#
  # job: techbase —— OPIC 技术底座应用指标(中心级,经 Traefik https)
  #--------------------------------------------------------------#
  - job_name: techbase
    metrics_path: /metrics
    scheme: https
    tls_config:
      insecure_skip_verify: true
    static_configs:
      - targets: ["techbase.opic-ai.ccoe.tech:443"]
        labels:
          cls: opic
          center: techbase
YML
fi
systemctl kill -s HUP vmetrics
# 2) vmalert 告警规则
cp vmalert-techbase.yml /infra/rules/techbase.yml
systemctl restart vmalert
# 3) Grafana 面板(Pigsty provider 扫描 /etc/dashboards/)
cp grafana-dashboard-opic-techbase.json /etc/dashboards/opic-techbase.json
echo "完成: vmetrics 抓取 + vmalert 规则 + Grafana 面板(约 10s 内生效)"
