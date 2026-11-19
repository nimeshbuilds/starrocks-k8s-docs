# 1. Architecture

How StarRocks is put together, and what the operator creates in Kubernetes.

## StarRocks components

| Component | Role | State | Kubernetes workload |
|---|---|---|---|
| **FE** (frontend) | Parses and plans SQL, holds metadata, coordinates queries. One FE is the leader, the rest are followers. | Stateful. Metadata lives on local disk and is replicated between FEs. | StatefulSet `<cluster>-fe` |
| **BE** (backend) | Stores data on local disk and executes queries. Used in shared-nothing clusters. | Stateful. | StatefulSet `<cluster>-be` |
| **CN** (compute node) | Executes queries. Holds only a local cache. Used in shared-data clusters and for elastic compute. | Stateless apart from cache. | StatefulSet `<cluster>-cn` |
| **FE proxy** | An nginx reverse proxy that lets clients outside the cluster network use Stream Load. Optional. | Stateless. | nginx pods managed by the operator |

FE is required. BE and CN are each optional, and a cluster can run both.

## Two cluster architectures

| | Shared-nothing | Shared-data |
|---|---|---|
| Where table data lives | Local disks of BE pods | Object storage such as S3 |
| Compute | BE | CN |
| FE setting | default | `run_mode = shared_data` in `fe.conf` |
| Scaling compute | Add BEs, data rebalances | Add or remove CNs, nothing to rebalance |
| Local disk on compute pods | Primary storage, must be persistent | Cache only, can be ephemeral |
| Typical use | Lowest and most predictable latency | Elastic compute, large or cold data, data lake queries |

You cannot convert a running cluster from one architecture to the other. Upstream says to deploy a new cluster instead. See [`upgrade.md`](../upstream/starrocks/docs/en/deployment/manage_deployment/upgrade.md).

Both architectures can query external data lakes (Hive, Iceberg, Delta Lake, Hudi, Paimon) through external catalogs. The data stays where it is. See [Data lake on S3 and Glue](10-data-lake-on-s3-and-glue.md).

## The operator model

The operator is a controller that watches two custom resources in the API group `starrocks.com/v1`:

| Kind | Short name | Purpose |
|---|---|---|
| `StarRocksCluster` | `src` | One StarRocks cluster: FE, plus optional BE, CN and FE proxy |
| `StarRocksWarehouse` | | An extra group of CNs attached to an existing cluster. Upstream documents warehouses as a StarRocks enterprise feature. |

You declare the cluster you want in a `StarRocksCluster` object. The operator creates and reconciles the StatefulSets, Services, ConfigMap mounts, PVCs and, when configured, a HorizontalPodAutoscaler.

Upstream describes it as a level 2 operator. It handles install, upgrade and scaling. It does not do backups, automatic tuning or self-healing beyond what Kubernetes controllers already provide.

```
            kubectl apply / helm install
                       |
                       v
            StarRocksCluster (CR)
                       |
        +--------------+---------------+
        |   StarRocks Operator         |   Deployment kube-starrocks-operator
        +--------------+---------------+
                       |
   +---------+---------+---------+-----------+
   |         |                   |           |
   v         v                   v           v
 FE STS    BE STS              CN STS     FE proxy (nginx)
 + svc     + svc               + svc      + svc
 + PVCs    + PVCs              + PVCs / emptyDir
                               + HPA (optional)
```

## What gets created for a cluster named `demo`

| Object | Name | Notes |
|---|---|---|
| StatefulSet | `demo-fe`, `demo-be`, `demo-cn` | One per enabled component |
| Pods | `demo-fe-0`, `demo-be-0`, `demo-cn-0`, ... | Ordinal pod names |
| Service (client) | `demo-fe-service`, `demo-be-service`, `demo-cn-service` | Configurable through `spec.<component>.service`. Use the FE service to connect. |
| Service (headless) | `demo-fe-search`, `demo-be-search`, `demo-cn-search` | Internal discovery. Do not connect clients to these. |
| PVC | `<volume-name>-<pod-name>`, for example `fe-meta-demo-fe-0` | One per entry in `storageVolumes`, per pod |
| HPA | `demo-cn-autoscaler` | Only when `autoScalingPolicy` is set on CN |

Pods register with the FE using their headless-service DNS names, for example `demo-cn-0.demo-cn-search.<namespace>.svc.cluster.local`. This is what appears in `SHOW FRONTENDS`, `SHOW BACKENDS` and `SHOW COMPUTE NODES`.

## Ports

| Component | Port | Config key | Purpose |
|---|---|---|---|
| FE | 8030 | `http_port` | HTTP, metrics at `/metrics`, Stream Load entry point |
| FE | 9020 | `rpc_port` | Thrift RPC |
| FE | 9030 | `query_port` | MySQL protocol. This is the port clients connect to. |
| FE | 9010 | `edit_log_port` | FE to FE metadata replication |
| FE | 6090 | `cloud_native_meta_port` | Shared-data metadata RPC |
| BE / CN | 9060 | `be_port` (older name `thrift_port`) | Thrift |
| BE / CN | 8040 | `be_http_port` (older name `webserver_port`) | HTTP, metrics at `/metrics` |
| BE / CN | 9050 | `heartbeat_service_port` | Heartbeat from FE |
| BE / CN | 8060 | `brpc_port` | Data exchange between nodes |
| BE / CN | 9070 | `starlet_port` | Shared-data agent |
| FE proxy | 8080 | | HTTP proxy for Stream Load |

More in [Ports, names and paths](reference/ports-and-paths.md).

## Container images

| Image | Used by |
|---|---|
| `starrocks/operator` | The operator |
| `starrocks/fe-ubuntu` | FE |
| `starrocks/be-ubuntu` | BE |
| `starrocks/cn-ubuntu` | CN |

Upstream examples use moving tags such as `latest` and `4.1-latest`. Pin an exact version tag in anything you care about, and mirror the images to your own registry if your clusters cannot pull from Docker Hub.

## Minimum platform versions

| Requirement | Version |
|---|---|
| Kubernetes | 1.23 or later |
| Helm, if used | 3.0 or later |
| metrics-server | Needed only for HPA-based CN autoscaling |

## Where to go next

- [Install the operator](02-install-operator.md)
- [Deploy a cluster](03-deploy-cluster.md)

## Upstream sources

- [`upstream/starrocks-kubernetes-operator/README.md`](../upstream/starrocks-kubernetes-operator/README.md)
- [`upstream/starrocks-kubernetes-operator/doc/deploy_starrocks_with_operator_howto.md`](../upstream/starrocks-kubernetes-operator/doc/deploy_starrocks_with_operator_howto.md)
- [`upstream/starrocks/docs/en/deployment/preparation/environment_configurations.md`](../upstream/starrocks/docs/en/deployment/preparation/environment_configurations.md)
- [`upstream/starrocks/docs/en/introduction/`](../upstream/starrocks/docs/en/introduction/)
