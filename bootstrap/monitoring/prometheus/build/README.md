# Build
The build directory wraps jsonnet configurations provided by [prometheus-operator/kube-prometheus](https://github.com/prometheus-operator/kube-prometheus/blob/main/docs/customizing.md) and overlays my specific configurations.

The `../install-prometheus.sh` script is intended to be idempotent and can be ran to iterate configuration changes to the prometheus.jsonnet configuration file.