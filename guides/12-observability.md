# 12. Observability

Metrics, dashboards and logs for a StarRocks cluster on Kubernetes.

## Metrics endpoints

| Component | Port | Path |
|---|---|---|
| FE | 8030 | `/metrics` |
| BE | 8040 | `/metrics` |
| CN | 8040 | `/metrics` |

All three expose Prometheus text format. There are three ways to get them scraped.

## Option 1: scrape annotations

Works with a plain Prometheus that discovers targets from annotations. Needs operator and chart 1.7.1 or later.

Helm, `kube-starrocks` chart:

```yaml
starrocks:
  starrocksFESpec:
    service:
      annotations:
        prometheus.io/path: "/metrics"
        prometheus.io/port: "8030"
        prometheus.io/scrape: "true"
  starrocksBeSpec:
    service:
      annotations:
        prometheus.io/path: "/metrics"
        prometheus.io/port: "8040"
        prometheus.io/scrape: "true"
  starrocksCnSpec:
    service:
      annotations:
        prometheus.io/path: "/metrics"
        prometheus.io/port: "8040"
        prometheus.io/scrape: "true"
```

Raw CR: put the same annotations under `spec.starRocksFeSpec.service.annotations` and so on.

Note that the upstream integration page spells the BE key `starrocksBESpec`. The chart's `values.yaml` uses `starrocksBeSpec`. Follow `values.yaml`.

## Option 2: ServiceMonitor

For clusters running the Prometheus Operator.

```yaml
# starrocks chart. Nest under `starrocks:` for kube-starrocks.
metrics:
  serviceMonitor:
    enabled: true
    labels:
      release: kube-prometheus-stack     # whatever your Prometheus selects on
    interval: 15s
```

Other keys under `metrics.serviceMonitor`:

| Key | Use |
|---|---|
| `basicAuth.enabled` with `usernameSecretName`, `usernameSecretKey`, `passwordSecretName`, `passwordSecretKey` | Scrape with basic auth |
| `endpointParam.enabled` with `params` | Add request parameters, for example `with_materialized_view_metrics: ["all"]` |

The installing identity needs rights on `servicemonitors` in the `monitoring.coreos.com` group.

## Option 3: PodMonitor

AWS Data on EKS uses three PodMonitors that match pods by component label and pick up every cluster in the namespace without per-cluster changes.

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: starrocks-fe
  namespace: starrocks
spec:
  selector:
    matchLabels:
      app.kubernetes.io/component: fe
  podMetricsEndpoints:
    - path: /metrics
      port: http-port
      interval: 15s
```

Their version also relabels: it takes the operator's pod label `app.starrocks.ownerreference/name` (for example `sr-fe`), strips the `-fe`, `-be` or `-cn` suffix, and writes the cluster name into the `job` label. A Grafana variable over `job` then lists every cluster. Full file: [`pod-monitors.yaml`](../upstream/data-on-eks/infra/terraform/manifests/starrocks/pod-monitors.yaml).

## Labels the operator puts on pods

| Label | Example | Use |
|---|---|---|
| `app.kubernetes.io/component` | `fe`, `be`, `cn` | Select all pods of a component |
| `app.starrocks.ownerreference/name` | `sr-fe` | Select one component of one cluster |

```bash
kubectl -n starrocks get pods -l app.kubernetes.io/component=cn
```

## Grafana

StarRocks publishes a Kubernetes dashboard:

https://github.com/StarRocks/starrocks/blob/main/extra/grafana/kubernetes/StarRocks-Overview-kubernetes-3.0.json

Import it in Grafana under Dashboards, New, Import, and choose your Prometheus data source.

Data on EKS ships its own multi-cluster dashboard at `infra/terraform/grafana-dashboards/starrocks-dashboard.json` in its repository. It is not copied here.

If you need to install Prometheus and Grafana first, upstream covers both the standalone charts and `kube-prometheus-stack` in [`deploy-prometheus-grafana.md`](../upstream/starrocks-kubernetes-operator/doc/integration/deploy-prometheus-grafana.md).

## What to watch

| Area | Signals |
|---|---|
| Availability | Pod readiness and restarts, `kubectl get starrockscluster` phase, FE count and leader presence |
| Query load | `starrocks_fe_query_total` rate, `starrocks_fe_connection_total`, query latency percentiles, query error rate |
| FE health | JVM heap use and GC time, metadata volume free space (FE stops below 5 Gi), edit log lag between FEs |
| BE and CN health | CPU and memory against limits, disk use on storage and cache volumes |
| Cache | Data cache hit ratio and disk use |
| Lake access | Object store request latency and errors, metastore call latency |
| Admission | Queued queries, queue wait time, queries terminated by big-query limits |
| Materialized views | Refresh success and duration |
| Autoscaling | HPA current and desired replicas, pending pods waiting for nodes |

Metric references in the upstream docs:

- [`monitoring/metric_details/`](../upstream/starrocks/docs/en/administration/management/monitoring/metric_details/)
- [`metrics-shared-data.md`](../upstream/starrocks/docs/en/administration/management/monitoring/metrics-shared-data.md)
- [`metrics-materialized_view.md`](../upstream/starrocks/docs/en/administration/management/monitoring/metrics-materialized_view.md)
- [`prometheus_grafana.md`](../upstream/starrocks/docs/en/administration/management/monitoring/prometheus_grafana.md)
- [`alert.md`](../upstream/starrocks/docs/en/administration/management/monitoring/alert.md)

## Datadog

The chart can add the annotations the Datadog agent looks for.

```yaml
# starrocks chart. Nest under `starrocks:` for kube-starrocks.
datadog:
  log:
    enabled: true
    logConfig: '{"tags": ["env:prod"]}'
    enableMultilineLogParsing: true      # FE uses a log4j pattern, BE and CN a glog pattern
  metrics:
    enabled: true
  profiling:
    fe: false
    be: false
    cn: false
    env: "starrocks-default"
    configMode: "service"
```

On the Datadog side, enable log collection and Prometheus scraping in the agent chart:

```yaml
datadog:
  logs:
    enabled: true
  prometheusScrape:
    enabled: true
    serviceEndpoints: true
```

Upstream page: [`integration-with-datadog.md`](../upstream/starrocks-kubernetes-operator/doc/integration/integration-with-datadog.md).

## Logs

### Where they are

| Component | Directory | Key files |
|---|---|---|
| FE | `/opt/starrocks/fe/log` | `fe.out`, `fe.log`, `fe.warn.log`, `fe.audit.log`, GC logs |
| BE | `/opt/starrocks/be/log` | `be.out`, `be.INFO`, `be.WARNING` |
| CN | `/opt/starrocks/cn/log` | `cn.out`, `cn.INFO`, `cn.WARNING` |

By default these directories are `emptyDir`, so logs from before a pod restart are gone. Do one of the following.

### Persist them

```yaml
starRocksFeSpec:
  storageVolumes:
    - name: fe-log
      storageSize: 10Gi
      mountPath: /opt/starrocks/fe/log
```

Helm: `storageSpec.logStorageSize`. Remember that `storageSpec.name` must be set for any PVC to be created.

### Send them to stdout

```yaml
starRocksFeSpec:
  feEnvVars:
    - name: LOG_CONSOLE
      value: "1"
```

Use `beEnvVars` and `cnEnvVars` for the others. Then `kubectl logs`, `kubectl logs -p` for the previous container, and any node-level log agent can read them.

Console logging is the simplest fit for a cluster that already ships container logs. Audit logs and big-query logs are separate files. If you need those in your log platform, persist the FE log directory and tail it with a sidecar, or use the audit loader.

### Log level

`sys_log_level` in each config file: `INFO` by default. Raise to `WARN` to cut volume.

### Operator logs

```bash
kubectl -n starrocks logs deploy/kube-starrocks-operator
```

Add `--zap-log-level 4` to the operator arguments for debug output.

## Query diagnostics

- **Query profile.** Shows operator-level timing, bytes read from cache versus remote storage, and where a query spent its time. See [`best_practices/query_tuning/`](../upstream/starrocks/docs/en/best_practices/query_tuning/).
- **`EXPLAIN` and `EXPLAIN ANALYZE`.** Show the plan and, for the latter, the runtime statistics.
- **Audit log.** One line per statement with user, time, scan rows, CPU cost and resource group.
- **`SHOW PROC`.** Live cluster state, for example `SHOW PROC '/current_queries'`, `SHOW PROC '/frontends'`, `SHOW PROC '/compute_nodes'`.
- **FE web UI.** `http://<fe>:8030`, reachable through a port-forward.

## Upstream sources

- [`integration-prometheus-grafana.md`](../upstream/starrocks-kubernetes-operator/doc/integration/integration-prometheus-grafana.md)
- [`deploy-prometheus-grafana.md`](../upstream/starrocks-kubernetes-operator/doc/integration/deploy-prometheus-grafana.md)
- [`integration-with-datadog.md`](../upstream/starrocks-kubernetes-operator/doc/integration/integration-with-datadog.md)
- [`logging_and_related_configurations_howto.md`](../upstream/starrocks-kubernetes-operator/doc/logging_and_related_configurations_howto.md)
- [`logs.md`](../upstream/starrocks/docs/en/administration/management/logs.md)
- [`monitoring/`](../upstream/starrocks/docs/en/administration/management/monitoring/)
