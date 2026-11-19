# Guides

Original, task-oriented documentation for running StarRocks on Kubernetes. Each guide ends with the upstream pages it draws on, so you can check details against the source.

## Reading order for a first deployment

1. [Architecture](01-architecture.md)
2. [Install the operator](02-install-operator.md)
3. [Deploy a cluster](03-deploy-cluster.md)
4. [Security](09-security.md), at least the root password section
5. [Networking and access](08-networking-and-access.md)
6. [Observability](12-observability.md)

Then whichever of the rest apply.

## All guides

| # | Guide | Covers |
|---|---|---|
| 1 | [Architecture](01-architecture.md) | FE, BE, CN, FE proxy. Shared-nothing and shared-data. What the operator creates. Ports and images. |
| 2 | [Install the operator](02-install-operator.md) | Manifests and Helm. Operator flags and chart values. Namespace scoping. GitOps and air-gapped installs. Upgrade and uninstall. |
| 3 | [Deploy a cluster](03-deploy-cluster.md) | Sizing. Shared-data on S3 and shared-nothing, by manifest and by Helm. Upstream examples. Verification. |
| 4 | [The StarRocksCluster resource](04-starrockscluster-resource.md) | Every spec field by purpose. Status. The warehouse resource. |
| 5 | [Configuration](05-configuration.md) | `fe.conf`, `be.conf`, `cn.conf`. Environment variables. Extra mounts. Entrypoints. Static and dynamic parameters. Graceful shutdown. |
| 6 | [Storage](06-storage.md) | What needs a disk. PVCs, `emptyDir`, `hostPath`, CSI. CN cache options. Multiple volumes. Retention. Read-only root filesystem. |
| 7 | [Scaling and autoscaling](07-scaling-and-autoscaling.md) | Manual scaling. FE and BE scale-in procedures. HPA and KEDA for CN. Node autoscaling. Warehouses. |
| 8 | [Networking and access](08-networking-and-access.md) | Services. Connecting. Load balancers. FE proxy for Stream Load. Traffic matrix. Outbound needs. |
| 9 | [Security](09-security.md) | Root password. Users and roles. TLS. Cloud credentials. Pod security. Installer permissions. SPIFFE. |
| 10 | [Data lake on S3 and Glue](10-data-lake-on-s3-and-glue.md) | Hive and Iceberg catalogs on AWS Glue. Metadata cache and freshness. Data cache. Materialized views. |
| 11 | [Resource management](11-resource-management.md) | Resource groups. Big-query limits. Query queues. Spill to disk. |
| 12 | [Observability](12-observability.md) | Prometheus by annotation, ServiceMonitor or PodMonitor. Grafana. Datadog. Logs. |
| 13 | [Upgrades and day-2 operations](13-upgrades-and-day-2.md) | StarRocks upgrade order. Operator and CRD upgrades. Rollout controls. Maintenance. Backup. |
| 14 | [Disaster recovery](14-disaster-recovery.md) | Cluster snapshots and the operator's restore mode for shared-data clusters. |
| 15 | [EKS reference](15-eks-reference.md) | What AWS Data on EKS deploys, and how to reuse it on an existing cluster. |
| 16 | [Troubleshooting](16-troubleshooting.md) | Symptoms, causes and fixes by area. |
| 17 | [Upstream documentation map](17-upstream-doc-map.md) | Topic to file index for everything under `upstream/`. |
| 18 | [AI agents and MCP](18-ai-agents-and-mcp.md) | The StarRocks MCP server and the guardrails automated callers need. |

## Reference

| File | Contents |
|---|---|
| [CRD API reference](reference/crd-api-reference.md) | All 37 types of `starrocks.com/v1` as Markdown tables |
| [Helm values reference](reference/helm-values-reference.md) | Values of the four charts, with the CR field each maps to |
| [Ports, names and paths](reference/ports-and-paths.md) | Ports, object names, DNS names, labels, paths, environment variables |

## Examples

| File | Contents |
|---|---|
| [`shared-data-s3.yaml`](examples/shared-data-s3.yaml) | `StarRocksCluster` with 3 FE and 3 CN on S3, with ConfigMaps |
| [`values-shared-data.yaml`](examples/values-shared-data.yaml) | The same cluster as Helm values, with CN autoscaling |
| [`glue-catalogs.sql`](examples/glue-catalogs.sql) | Hive and Iceberg catalogs on AWS Glue, refresh, grants, a rollup view |
| [`resource-groups.sql`](examples/resource-groups.sql) | Resource groups, query queues and spill for three workloads |

The examples are starting points with placeholders. They have not been run against a live cluster. Test them in a non-production environment.

## Conventions

- `sr` is the example cluster name and `starrocks` the example namespace.
- `<angle brackets>` mark values you must replace.
- CR field names are written as in the custom resource, for example `starRocksFeSpec`. Helm value names are written as in `values.yaml`, for example `starrocksFESpec`. The two differ. See the [Helm values reference](reference/helm-values-reference.md#key-spelling-helm-versus-cr).
- Defaults quoted in the guides come from the upstream copies in this repository: StarRocks `branch-4.1` and operator chart `1.11.8`. Check your own version.

## Accuracy

These guides were written by reading the upstream material under `upstream/`. Where upstream is silent or ambiguous, the guide says so. Statements about behaviour that upstream does not document are marked as such, and none of the commands were executed against a running cluster while writing. If a guide and an upstream page disagree, trust the upstream page for your version.
