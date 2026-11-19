# 17. Upstream documentation map

Where to find a topic in the upstream copies. Paths are relative to the repository root.

Three trees:

| Tree | Root | Size |
|---|---|---|
| StarRocks docs | `upstream/starrocks/docs/en/` | About 1,170 Markdown pages |
| Operator docs | `upstream/starrocks-kubernetes-operator/` | About 30 how-to pages, 11 example manifests, 4 chart value files |
| Data on EKS | `upstream/data-on-eks/` | 4 pages, 7 manifests |

## Operator: by task

| Task | File under `upstream/starrocks-kubernetes-operator/` |
|---|---|
| Overview and quick install | `README.md` |
| Install operator and cluster with manifests | `doc/deploy_starrocks_with_operator_howto.md` |
| Install with Helm | `doc/deploy_starrocks_with_helm_howto.md`, `doc/add_helm_repo_howto.md` |
| Chart documentation | `helm-charts/charts/kube-starrocks/README.md`, `.../charts/operator/README.md`, `.../charts/starrocks/README.md`, `helm-charts/charts/warehouse/README.md` |
| Every Helm value, with comments | `helm-charts/charts/kube-starrocks/charts/starrocks/values.yaml`, `.../charts/operator/values.yaml`, `helm-charts/charts/kube-starrocks/values.yaml` (umbrella), `helm-charts/charts/warehouse/values.yaml` |
| CRD field reference | `doc/api.md` (HTML). Markdown version: `guides/reference/crd-api-reference.md` |
| CRD schemas | `deploy/starrocks.com_starrocksclusters.yaml`, `deploy/starrocks.com_starrockswarehouses.yaml` |
| Operator manifest, RBAC, flags | `deploy/operator.yaml` |
| Example clusters | `examples/starrocks/*.yaml`, indexed in `examples/starrocks/README.md` |
| Run several clusters | `doc/deploy_multiple_clusters_howto.md` |
| Installer permissions | `doc/least_permission_to_deploy_starrocks_howto.md` |
| Root password at install | `doc/initialize_root_password_howto.md` |
| Root password later | `doc/change_root_password_howto.md` |
| Operator to FE over TLS | `doc/connect_to_ssl_enabled_fe_howto.md` |
| Persistent volumes | `doc/mount_persistent_volume_howto.md` |
| Several data volumes | `doc/use_multiple_volumes_how_to.md` |
| CSI ephemeral volumes, SPIFFE | `doc/mount_csi_volumes_howto.md` |
| Extra ConfigMaps and Secrets | `doc/mount_external_configmaps_or_secrets_howto.md` |
| Read-only root filesystem | `doc/setup-starrocks-when-readOnlyRootFilesystem-is-true.md` |
| CN autoscaling, operator 1.11.0 and later | `doc/hpa_dynamic_scaling_with_helm_howto.md` |
| CN autoscaling, earlier operators | `doc/automatic_scaling_for_cn_nodes_howto.md` |
| Scale in FE | `doc/scale_in_fe_nodes_howto.md` |
| Scale in BE | `doc/scale_in_shared_nothing_cluster_howto.md` |
| Warehouses | `doc/deploy_warehouse_howto.md` |
| Disaster recovery, shared-data | `doc/disaster_recovery_for_shared_data_cluster_howto.md` |
| Stream Load from outside, FE proxy | `doc/load_data_using_stream_load_howto.md` |
| Logging | `doc/logging_and_related_configurations_howto.md` |
| Prometheus and Grafana | `doc/integration/integration-prometheus-grafana.md`, `doc/integration/deploy-prometheus-grafana.md` |
| Datadog | `doc/integration/integration-with-datadog.md` |
| Local test install (kind, minikube) | `doc/local_installation_how_to.md` |
| Build the operator image | `doc/build_your_own_container_image_howto.md`, `doc/build_the_operator_images_by_yourself_howto.md` |
| Release history up to 1.9.8 | `CHANGELOG.md` |
| Chinese versions of two pages | `doc/cn/`, `README_ZH-CN.md` |

## StarRocks docs: by section

Under `upstream/starrocks/docs/en/`:

| Directory | Pages | Covers |
|---|---|---|
| `introduction/` | 4 | What StarRocks is, architecture, features |
| `quick_start/` | 8 | Tutorials: shared-nothing, shared-data, Helm, Iceberg, Hudi, routine load, MCP |
| `deployment/` | 15 | Planning, prerequisites, manual deploy, operator and Helm deploy, upgrade, downgrade, post-deployment |
| `table_design/` | 23 | Table types, partitioning, bucketing, indexes |
| `loading/` | 38 | Stream Load, Broker Load, Kafka, Flink, Spark, object storage, `INSERT` |
| `unloading/` | 8 | Export, `INSERT INTO FILES` |
| `data_source/` | 30 | External catalogs, data lake analytics, data cache |
| `using_starrocks/` | 31 | Materialized views, optimizer statistics, query cache, join strategies |
| `administration/` | 71 | Configuration reference, management, monitoring, resource management, users and privileges, recovery |
| `integrations/` | 45 | BI tools, loading tools, streaming, cloud authentication |
| `sql-reference/` | 785 | Statements, functions, data types, system variables, `information_schema` |
| `best_practices/` | 18 | Partitioning, bucketing, primary key tables, query tuning, FE memory |
| `benchmarking/` | 5 | SSB, TPC-H, TPC-DS results and queries |
| `faq/` | 21 | Deployment, SQL, operations, shared-data, data lake, resource isolation |
| `release_notes/` | 20 | Per-version release notes |
| `developers/` | 18 | Building from source, code style, tracing |
| `maturity/` | 3 | Feature maturity levels |
| `_assets/` | | Images, and shared snippets in `_assets/commonMarkdown/` |

## StarRocks docs: by topic

### Deployment and Kubernetes

| Topic | File |
|---|---|
| Deployment overview | `deployment/deployment.md` |
| Operator deployment | `deployment/sr_operator.md` |
| Helm deployment | `deployment/helm.md`, `quick_start/helm.md` |
| Cluster sizing | `deployment/preparation/plan_cluster.md` |
| Ports, OS settings | `deployment/preparation/environment_configurations.md` |
| Prerequisites | `deployment/preparation/deployment_prerequisites.md` |
| Shared-data deployment and S3 settings | `deployment/deploy_shared_data_manually.md`, `quick_start/shared-data.md` |
| Shared-data feature support and limits | `deployment/feature-support-shared-data.md` |
| Upgrade, downgrade | `deployment/manage_deployment/upgrade.md`, `.../downgrade.md` |
| After deployment | `deployment/manage_deployment/post_deployment_setup.md` |

### Configuration reference

| Topic | File |
|---|---|
| FE parameters | `administration/configuration/FE_parameters/FE_parameters.md` and the files beside it: `log_server_meta.md`, `user_query_loading.md`, `stats_storage.md`, `shared_lake_other.md` |
| BE and CN parameters | `administration/configuration/BE_parameters/BE_parameters.md` and the files beside it: `log_server_meta.md`, `query_loading.md`, `stats_storage.md`, `shared_lake_other.md` |
| Shared-data and S3 FE settings | `administration/configuration/FE_parameters/shared_lake_other.md` |
| System and session variables | `sql-reference/System_variable.md` |
| System limits | `sql-reference/System_limit.md` |
| Error codes | `sql-reference/Error_code.md` |

### Data lake

| Topic | File |
|---|---|
| Catalog concepts | `data_source/catalog/catalog_overview.md` |
| Hive catalog, including AWS Glue | `data_source/catalog/hive_catalog.md` |
| Iceberg catalog | `data_source/catalog/iceberg/iceberg.md`, with `DDL.md`, `DML.md`, `procedures.md`, `iceberg_timetravel.md`, `iceberg_meta_table.md`, `iceberg_rest_s3.md`, `iceberg_rest_security.md` |
| Delta Lake, Hudi, Paimon, JDBC, Elasticsearch, Kudu, MaxCompute | `data_source/catalog/<name>_catalog.md` |
| Unified catalog | `data_source/catalog/unified_catalog.md` |
| Feature support matrix | `data_source/feature-support-data-lake-analytics.md` |
| Data cache | `data_source/data_cache/data_cache.md`, `block_cache_warmup.md`, `data_cache_observe.md`, `data_cache_troubleshooting.md` |
| Data lake FAQ | `data_source/datalake_faq.md` |
| AWS authentication | `integrations/csp_auth/authenticate_to_aws_resources.md` |
| AWS IAM policy examples | `sql-reference/aws_iam_policies.md` |
| Storage volumes | `sql-reference/sql-statements/cluster-management/storage_volume/` |

### Materialized views and query acceleration

| Topic | File |
|---|---|
| Asynchronous materialized views | `using_starrocks/async_mv/Materialized_view.md` |
| Views over data lakes | `using_starrocks/async_mv/use_cases/data_lake_query_acceleration_with_materialized_views.md` |
| Query rewrite | `using_starrocks/async_mv/use_cases/query_rewrite_with_materialized_views.md` |
| Optimizer statistics | `using_starrocks/Cost_based_optimizer.md` |
| Query cache | `using_starrocks/caching/` |
| Query tuning and profiles | `best_practices/query_tuning/` |

### Operations

| Topic | File |
|---|---|
| Resource groups | `administration/management/resource_management/resource_group.md` |
| Query queues | `administration/management/resource_management/query_queues.md` |
| Spill to disk | `administration/management/resource_management/spill_to_disk.md` |
| Memory | `administration/management/resource_management/Memory_management.md` |
| Big queries | `administration/management/monitor_manage_big_queries.md` |
| Resource groups from audit logs | `best_practices/audit_log_resource_group.md` |
| Scale | `administration/management/Scale_up_down.md` |
| Cluster snapshots | `administration/management/cluster_snapshot.md` |
| Backup and restore | `administration/management/Backup_and_restore.md` |
| Metadata and data recovery | `administration/Meta_recovery.md`, `administration/Data_recovery.md` |
| Graceful exit | `administration/management/graceful_exit.md` |
| Logs | `administration/management/logs.md` |
| Audit loader | `administration/management/audit_loader.md` |
| Compaction | `administration/management/compaction.md` |
| Metrics, Prometheus, alerts | `administration/management/monitoring/` |
| HTTP interface | `administration/http_interface/` |

### Security

| Topic | File |
|---|---|
| Users, roles, privileges | `administration/user_privs/`, with `authentication/` and `authorization/` |
| SSL authentication | `administration/user_privs/ssl_authentication.md` |
| Group providers | `administration/user_privs/group_provider.md` |
| Best practices | `best_practices/authentication_authorization.md` |
| `GRANT`, `CREATE USER` and related | `sql-reference/sql-statements/account-management/` |

### SQL reference

| Topic | Path |
|---|---|
| Statements by area | `sql-reference/sql-statements/` with `Catalog/`, `Database/`, `table_bucket_part_index/`, `materialized_view/`, `loading_unloading/`, `cluster-management/`, `account-management/`, `backup_restore/`, `cbo_stats/`, `Resource/`, `Function/`, `View/`, `dictionary/` |
| Functions | `sql-reference/sql-functions/<category>/` |
| Data types | `sql-reference/data-types/` |
| `information_schema` | `sql-reference/information_schema/` |
| Trino SQL translation | `sql-reference/sql-statements/TRANSLATE_TRINO.md` |
| SQL over HTTP | `sql-reference/http_sql_api.md` |

### Integrations

| Topic | Path |
|---|---|
| BI tools: Superset, Tableau, Metabase, Hex and others | `integrations/BI_integrations/` |
| Kafka, Flink, Spark connectors | `integrations/streaming/`, `integrations/loading_tools/`, `loading/` |
| MCP server quick start | `quick_start/MCP.md` |

## Data on EKS

| Topic | File under `upstream/data-on-eks/` |
|---|---|
| Stack overview | `website/docs/datastacks/databases/starrocks-on-eks/index.md` |
| Infrastructure guide | `website/docs/datastacks/databases/starrocks-on-eks/infra.md` |
| TPC-DS benchmark guide | `website/docs/datastacks/databases/starrocks-on-eks/tpcds-benchmark.md` |
| Benchmark results | `website/docs/benchmarks/starrocks-benchmark.md` |
| Shared-data cluster | `data-stacks/starrocks-on-eks/examples/starrocks-shared-data.yaml` |
| Shared-nothing cluster | `data-stacks/starrocks-on-eks/examples/starrocks-shared-nothing.yaml` |
| KEDA scaler | `infra/terraform/manifests/starrocks/cn-keda-scaledobject.yaml` |
| PodMonitors | `infra/terraform/manifests/starrocks/pod-monitors.yaml` |
| StorageClass | `infra/terraform/manifests/starrocks/storageclass.yaml` |
| Operator Helm values | `infra/terraform/helm-values/starrocks-operator.yaml` |
| Argo CD Application | `infra/terraform/argocd-applications/starrocks-operator.yaml` |

## Reading the StarRocks pages

- Files are Docusaurus sources. Front matter at the top carries the title and description.
- `.mdx` pages may import snippets, for example `import X from '../_assets/commonMarkdown/...mdx'`. Follow the import to read the text.
- Links between pages are relative paths within `docs/en/`.
- `:::note`, `:::tip` and `:::warning` blocks are callouts.
- `<Tabs>` and `<TabItem>` blocks hold alternatives, such as one tab per cloud provider.
- Image links point into `_assets/`.
