# Ports, names and paths

Quick reference for a cluster named `<c>` in namespace `<ns>`.

## Ports

| Component | Port | Config key | Protocol | Purpose |
|---|---|---|---|---|
| FE | 8030 | `http_port` | HTTP | Web UI, REST API, Stream Load entry, `/metrics` |
| FE | 9020 | `rpc_port` | Thrift | RPC from BE and CN |
| FE | 9030 | `query_port` | MySQL | Client connections |
| FE | 9010 | `edit_log_port` | | Metadata replication between FEs |
| FE | 6090 | `cloud_native_meta_port` | RPC | Shared-data metadata |
| BE, CN | 9060 | `be_port` or `thrift_port` | Thrift | Tasks from FE |
| BE, CN | 8040 | `be_http_port` or `webserver_port` | HTTP | REST API, `/metrics` |
| BE, CN | 9050 | `heartbeat_service_port` | Thrift | Heartbeats from FE. Also the port used to identify a node in SQL. |
| BE, CN | 8060 | `brpc_port` | bRPC | Data exchange between nodes |
| BE, CN | 9070 | `starlet_port` | | Shared-data agent |
| FE proxy | 8080 | | HTTP | Stream Load proxy |

Service port names on FE: `http`, `query`, `rpc`, `edit-log`. On the FE proxy: `http-port`.

## Kubernetes object names

| Object | Name |
|---|---|
| Custom resource | `starrocksclusters.starrocks.com`, short name `src` |
| Custom resource | `starrockswarehouses.starrocks.com` |
| Operator Deployment | `kube-starrocks-operator`, container `manager` |
| Operator ServiceAccount | `starrocks` |
| Operator ClusterRole | `kube-starrocks-operator` |
| FE StatefulSet | `<c>-fe` |
| BE StatefulSet | `<c>-be` |
| CN StatefulSet | `<c>-cn` |
| Warehouse CN StatefulSet | `<warehouse>-warehouse-cn` |
| Client Services | `<c>-fe-service`, `<c>-be-service`, `<c>-cn-service` |
| Headless Services | `<c>-fe-search`, `<c>-be-search`, `<c>-cn-search` |
| CN HPA | `<c>-cn-autoscaler` |
| Warehouse HPA | `<warehouse>-warehouse-cn-autoscaler` |
| PVC | `<volume-name>-<pod-name>` |
| Helm entrypoint ConfigMap | `<c>-<component>-entrypoint-script` |

With the Helm charts, `<c>` defaults to `kube-starrocks`.

## DNS names

| What | Name |
|---|---|
| FE endpoint for clients | `<c>-fe-service.<ns>.svc.cluster.local:9030` |
| An FE pod | `<c>-fe-0.<c>-fe-search.<ns>.svc.cluster.local` |
| A BE pod | `<c>-be-0.<c>-be-search.<ns>.svc.cluster.local` |
| A CN pod | `<c>-cn-0.<c>-cn-search.<ns>.svc.cluster.local` |

Node addresses in SQL use the pod DNS name and a port:

```sql
ALTER SYSTEM DROP FOLLOWER       "<c>-fe-4.<c>-fe-search.<ns>.svc.cluster.local:9010";
ALTER SYSTEM DECOMMISSION BACKEND "<c>-be-5.<c>-be-search.<ns>.svc.cluster.local:9050";
ALTER SYSTEM DROP BACKEND        "<c>-be-5.<c>-be-search.<ns>.svc.cluster.local:9050";
ALTER SYSTEM DROP COMPUTE NODE   "<c>-cn-3.<c>-cn-search.<ns>.svc.cluster.local:9050";
```

## Pod labels

| Label | Values |
|---|---|
| `app.kubernetes.io/component` | `fe`, `be`, `cn` |
| `app.starrocks.ownerreference/name` | `<c>-fe`, `<c>-be`, `<c>-cn` |

## Annotations

| Annotation | On | Meaning |
|---|---|---|
| `app.starrocks.io/fe-config-hash`, `be-config-hash`, `cn-config-hash` | Component spec, set by the Helm chart | Config hash that triggers a rollout when config changes |
| `starrocks.com/skip-fe-cleanup: "true"` | `StarRocksWarehouse` | Keep the warehouse in StarRocks when the CR is deleted |
| `prometheus.io/scrape`, `prometheus.io/port`, `prometheus.io/path` | Component service | Annotation-based scraping |

## Paths in the containers

| Component | Path | Contents |
|---|---|---|
| FE | `/opt/starrocks/fe/conf/fe.conf` | Config. Symlink to `/etc/starrocks/fe/conf/fe.conf`. |
| FE | `/opt/starrocks/fe/meta` | Metadata |
| FE | `/opt/starrocks/fe/log` | `fe.out`, `fe.log`, `fe.warn.log`, `fe.audit.log`, `fe.gc.log.*`, `fe.big_query.log` |
| FE | `/opt/starrocks/fe_entrypoint.sh`, `/opt/starrocks/fe_prestop.sh` | Entrypoint and `preStop` scripts |
| BE | `/opt/starrocks/be/conf/be.conf` | Config. Symlink to `/etc/starrocks/be/conf/be.conf`. |
| BE | `/opt/starrocks/be/storage` | Data |
| BE | `/opt/starrocks/be/log` | `be.out`, `be.INFO`, `be.WARNING` |
| BE | `/opt/starrocks/be/spill` | Spill directory |
| BE | `/opt/starrocks/be_entrypoint.sh`, `/opt/starrocks/be_prestop.sh` | Scripts |
| CN | `/opt/starrocks/cn/conf/cn.conf` | Config |
| CN | `/opt/starrocks/cn/storage` | Cache. In shared-data mode the cache is under `starlet_cache/`. |
| CN | `/opt/starrocks/cn/log` | `cn.out`, `cn.INFO`, `cn.WARNING` |
| CN | `/opt/starrocks/cn/spill` | Spill directory |
| CN | `/opt/starrocks/cn_entrypoint.sh`, `/opt/starrocks/cn_prestop.sh` | Scripts |
| Helm custom entrypoint | `/etc/starrocks/entrypoint.sh` | Mounted script |

## Environment variables

| Variable | Meaning |
|---|---|
| `FE_SERVICE_NAME` | Passed to the entrypoint scripts |
| `MYSQL_PWD` | Root password for component scripts |
| `LOG_CONSOLE` | `1` sends logs to stdout |
| `TZ` | Time zone |
| `STARROCKS_ROOT` | Alternate install root |
| `RESTORE_CLUSTER_GENERATION`, `RESTORE_CLUSTER_SNAPSHOT` | Set by the operator during a disaster recovery restore |
| `KUBE_STARROCKS_UNSUPPORTED_ENVS` | On the operator: variables that must not be passed to StarRocks containers |

## Images

| Image | Default tag in chart 1.11.8 |
|---|---|
| `starrocks/operator` | `v1.11.8` |
| `starrocks/fe-ubuntu` | `4.1-latest` |
| `starrocks/be-ubuntu` | `4.1-latest` |
| `starrocks/cn-ubuntu` | `4.1-latest` |
| FE proxy | `nginx:1.24.0` |

## Chart repository

```
https://starrocks.github.io/starrocks-kubernetes-operator
```

Charts: `kube-starrocks`, `operator`, `starrocks`, `warehouse`.

## SQL you will use often

```sql
SHOW FRONTENDS;
SHOW BACKENDS;
SHOW COMPUTE NODES;
SHOW WAREHOUSES;
SHOW STORAGE VOLUMES;
SHOW CATALOGS;
SHOW RESOURCE GROUPS ALL;
SHOW PROC '/current_queries';
SET PASSWORD = PASSWORD('<password>');
ADMIN SET FRONTEND CONFIG ("key" = "value");
REFRESH EXTERNAL TABLE <catalog>.<db>.<table>;
```
