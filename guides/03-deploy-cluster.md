# 3. Deploy a cluster

A cluster is one `StarRocksCluster` object. You can write it by hand or let the `starrocks` Helm chart render it. Both end up as the same custom resource.

The operator must be running first. See [Install the operator](02-install-operator.md).

## Choose an architecture

| You want | Deploy | Components |
|---|---|---|
| Data on local disks, lowest latency | Shared-nothing | 3 FE + 3 or more BE |
| Data in S3, elastic compute | Shared-data | 3 FE + CN |
| Only to query an existing data lake | Shared-data is the usual fit, since CNs are stateless | 3 FE + CN |

Three FEs give high availability. With one FE the cluster stops when that pod stops. Once you run three FEs, do not scale FE below three.

## Sizing starting points

From the upstream cluster planning page:

| Component | CPU | Memory | Disk |
|---|---|---|---|
| FE | 8 cores | 16 GB | 100 GB is enough for metadata in most cases. The FE stops if free space on the metadata volume drops below 5 Gi. |
| BE | 16 cores | 64 GB | Raw data size x replica count / compression ratio, plus headroom |
| CN | 16 cores | 64 GB | Sized to the hot data you want cached |

Set `requests` equal to `limits` on BE and CN if you autoscale on utilization, so the percentage means something.

## Path 1: a `StarRocksCluster` manifest

### Shared-data cluster on S3

A complete example is in [`examples/shared-data-s3.yaml`](examples/shared-data-s3.yaml). The essentials:

```yaml
apiVersion: starrocks.com/v1
kind: StarRocksCluster
metadata:
  name: sr
  namespace: starrocks
spec:
  starRocksFeSpec:
    image: starrocks/fe-ubuntu:<version>
    replicas: 3
    requests: {cpu: 8, memory: 16Gi}
    limits:   {cpu: 8, memory: 16Gi}
    serviceAccount: starrocks-sa          # carries the IAM permissions for S3
    configMapInfo:
      configMapName: sr-fe-cm
      resolveKey: fe.conf
    storageVolumes:
      - name: fe-meta
        storageClassName: gp3
        storageSize: 100Gi
        mountPath: /opt/starrocks/fe/meta
      - name: fe-log
        storageClassName: gp3
        storageSize: 10Gi
        mountPath: /opt/starrocks/fe/log
  starRocksCnSpec:
    image: starrocks/cn-ubuntu:<version>
    replicas: 3
    requests: {cpu: 16, memory: 64Gi}
    limits:   {cpu: 16, memory: 64Gi}
    serviceAccount: starrocks-sa
    configMapInfo:
      configMapName: sr-cn-cm
      resolveKey: cn.conf
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: sr-fe-cm
  namespace: starrocks
data:
  fe.conf: |
    LOG_DIR = ${STARROCKS_HOME}/log
    DATE = "$(date +%Y%m%d-%H%M%S)"
    JAVA_OPTS="-Dlog4j2.formatMsgNoLookups=true -Xmx8192m -XX:+UseG1GC -Xlog:gc*:${LOG_DIR}/fe.gc.log.$DATE:time"
    http_port = 8030
    rpc_port = 9020
    query_port = 9030
    edit_log_port = 9010
    mysql_service_nio_enabled = true
    sys_log_level = INFO

    run_mode = shared_data
    cloud_native_meta_port = 6090
    enable_load_volume_from_conf = true
    cloud_native_storage_type = S3
    aws_s3_path = <bucket>/<prefix>
    aws_s3_region = <region>
    aws_s3_use_aws_sdk_default_behavior = true
```

Key points for shared-data mode:

- `run_mode = shared_data` and `cloud_native_meta_port` go in `fe.conf`.
- With `enable_load_volume_from_conf = true`, FE builds a default storage volume from the `aws_s3_*` settings at first start. With `false`, you create the storage volume yourself in SQL after the cluster is up:

  ```sql
  CREATE STORAGE VOLUME def_volume
  TYPE = S3
  LOCATIONS = ("s3://<bucket>/<prefix>")
  PROPERTIES (
      "enabled" = "true",
      "aws.s3.region" = "<region>",
      "aws.s3.use_aws_sdk_default_behavior" = "true"
  );
  SET def_volume AS DEFAULT STORAGE VOLUME;
  ```

- `aws_s3_path` is documented as the bucket name plus an optional sub-path, for example `testbucket/subpath`. The Data on EKS example writes it with an `s3://` prefix. Follow the format in the FE parameter reference for your version: [`shared_lake_other.md`](../upstream/starrocks/docs/en/administration/configuration/FE_parameters/shared_lake_other.md).
- `cloud_native_storage_type` defaults to `S3` and `enable_load_volume_from_conf` defaults to `false`.
- Prefer IAM roles over static keys. `aws_s3_use_aws_sdk_default_behavior = true` lets the AWS SDK credential chain pick up IRSA or EKS Pod Identity from the pod's ServiceAccount. The Data on EKS example also sets `aws_s3_use_instance_profile = true`. Static `aws_s3_access_key` and `aws_s3_secret_key` work but put secrets in a ConfigMap.
- The upstream operator example for shared-data mode ships with `enable_load_volume_from_conf = false` and no S3 settings. You must edit it before use.
- CN local disk is a cache. See [Storage](06-storage.md#cn-cache-disks) for the options, including running with no cache disk.

### Shared-nothing cluster

```yaml
apiVersion: starrocks.com/v1
kind: StarRocksCluster
metadata:
  name: sr
  namespace: starrocks
spec:
  starRocksFeSpec:
    image: starrocks/fe-ubuntu:<version>
    replicas: 3
    requests: {cpu: 8, memory: 16Gi}
    limits:   {cpu: 8, memory: 16Gi}
    storageVolumes:
      - {name: fe-meta, storageSize: 100Gi, mountPath: /opt/starrocks/fe/meta}
      - {name: fe-log,  storageSize: 10Gi,  mountPath: /opt/starrocks/fe/log}
  starRocksBeSpec:
    image: starrocks/be-ubuntu:<version>
    replicas: 3
    requests: {cpu: 16, memory: 64Gi}
    limits:   {cpu: 16, memory: 64Gi}
    storageVolumes:
      - {name: be-data, storageSize: 1Ti, mountPath: /opt/starrocks/be/storage}
      - {name: be-log,  storageSize: 10Gi, mountPath: /opt/starrocks/be/log}
```

Without `storageVolumes` the operator uses `emptyDir`, and FE metadata and BE data are lost when a pod restarts. Always set persistent volumes for FE metadata and BE data.

### Apply it

```bash
kubectl apply -f cluster.yaml
kubectl -n starrocks get starrockscluster
kubectl -n starrocks get pods -w
```

FE pods start first. BE and CN pods start after an FE is ready.

### Upstream example manifests

| File | What it shows |
|---|---|
| [`deploy_a_starrocks_cluster_with_no_ha.yaml`](../upstream/starrocks-kubernetes-operator/examples/starrocks/deploy_a_starrocks_cluster_with_no_ha.yaml) | Smallest possible cluster |
| [`deploy_a_ha_starrocks_cluster.yaml`](../upstream/starrocks-kubernetes-operator/examples/starrocks/deploy_a_ha_starrocks_cluster.yaml) | 3 FE + 3 BE |
| [`starrocks-fe-and-be.yaml`](../upstream/starrocks-kubernetes-operator/examples/starrocks/starrocks-fe-and-be.yaml) | The sample used in the upstream how-to |
| [`deploy_a_starrocks_cluster_with_cn.yaml`](../upstream/starrocks-kubernetes-operator/examples/starrocks/deploy_a_starrocks_cluster_with_cn.yaml) | FE + BE + CN with HPA |
| [`deploy_a_starrocks_cluster_with_custom_configurations.yaml`](../upstream/starrocks-kubernetes-operator/examples/starrocks/deploy_a_starrocks_cluster_with_custom_configurations.yaml) | ConfigMaps for `fe.conf`, `be.conf`, `cn.conf` |
| [`deploy_a_starrocks_cluster_with_persistent_storage.yaml`](../upstream/starrocks-kubernetes-operator/examples/starrocks/deploy_a_starrocks_cluster_with_persistent_storage.yaml) | PVC-backed volumes |
| [`deploy_a_starrocks_cluster_running_in_shared_data_mode.yaml`](../upstream/starrocks-kubernetes-operator/examples/starrocks/deploy_a_starrocks_cluster_running_in_shared_data_mode.yaml) | Shared-data skeleton |
| [`deploy_a_starrocks_cluster_with_fe_proxy.yaml`](../upstream/starrocks-kubernetes-operator/examples/starrocks/deploy_a_starrocks_cluster_with_fe_proxy.yaml) | FE proxy and NodePort services |
| [`deploy_a_starrocks_cluster_with_be_capabilities.yaml`](../upstream/starrocks-kubernetes-operator/examples/starrocks/deploy_a_starrocks_cluster_with_be_capabilities.yaml) | Linux capabilities on BE |
| [`deploy_a_starrocks_cluster_with_all_features.yaml`](../upstream/starrocks-kubernetes-operator/examples/starrocks/deploy_a_starrocks_cluster_with_all_features.yaml) | Every field, annotated |

AWS Data on EKS adds two production-shaped examples: [`starrocks-shared-data.yaml`](../upstream/data-on-eks/data-stacks/starrocks-on-eks/examples/starrocks-shared-data.yaml) and [`starrocks-shared-nothing.yaml`](../upstream/data-on-eks/data-stacks/starrocks-on-eks/examples/starrocks-shared-nothing.yaml).

## Path 2: the `starrocks` Helm chart

```bash
helm install sr starrocks/starrocks -n starrocks -f my-values.yaml
```

A shared-data values file is in [`examples/values-shared-data.yaml`](examples/values-shared-data.yaml). The shape:

```yaml
starrocksCluster:
  enabledBe: false
  enabledCn: true

starrocksFESpec:
  replicas: 3
  image: {repository: starrocks/fe-ubuntu, tag: "<version>"}
  resources:
    requests: {cpu: 8, memory: 16Gi}
    limits:   {cpu: 8, memory: 16Gi}
  storageSpec:
    name: fe
    storageClassName: gp3
    storageSize: 100Gi
    logStorageSize: 10Gi
  config: |
    ...
    run_mode = shared_data
    cloud_native_meta_port = 6090
    enable_load_volume_from_conf = true
    cloud_native_storage_type = S3
    aws_s3_path = <bucket>/<prefix>
    aws_s3_region = <region>
    aws_s3_use_aws_sdk_default_behavior = true

starrocksCnSpec:
  image: {repository: starrocks/cn-ubuntu, tag: "<version>"}
  replicas: 3
  resources:
    requests: {cpu: 16, memory: 64Gi}
    limits:   {cpu: 16, memory: 64Gi}
```

Things that differ from the raw CR:

- Keys are spelled `starrocksFESpec`, `starrocksBeSpec`, `starrocksCnSpec`, `starrocksFeProxySpec`. The CR uses `starRocksFeSpec`, `starRocksBeSpec`, `starRocksCnSpec`, `starRocksFeProxySpec`.
- `enabledBe` defaults to `true` and `enabledCn` to `false`. Flip both for shared-data.
- Config goes inline in `config:` and the chart creates the ConfigMap. `configyaml:` is a map alternative that replaces `config:` when set.
- Storage is described by `storageSpec` and the chart derives the volume names and mount paths.
- Under the `kube-starrocks` umbrella chart, all of this is nested under `starrocks:`.

All values are listed in [Helm values reference](reference/helm-values-reference.md).

## Verify

```bash
kubectl -n starrocks get starrockscluster
# NAME   PHASE     FESTATUS   BESTATUS   CNSTATUS
# sr     running   running               running

kubectl -n starrocks get pods,svc,pvc
```

Connect and check node registration:

```bash
kubectl -n starrocks port-forward svc/sr-fe-service 9030:9030
mysql -h 127.0.0.1 -P 9030 -u root
```

```sql
SHOW FRONTENDS;
SHOW BACKENDS;        -- shared-nothing
SHOW COMPUTE NODES;   -- shared-data
SHOW STORAGE VOLUMES; -- shared-data
```

A new cluster has an empty `root` password. Set one before exposing the service. See [Security](09-security.md#root-password).

## After the first deploy

1. Set the root password.
2. Pin image tags.
3. Decide how clients reach FE. See [Networking and access](08-networking-and-access.md).
4. Turn on metrics scraping. See [Observability](12-observability.md).
5. For data lake queries, create an external catalog. See [Data lake on S3 and Glue](10-data-lake-on-s3-and-glue.md).
6. Create resource groups before opening the cluster to mixed workloads. See [Resource management](11-resource-management.md).

## Delete a cluster

```bash
kubectl -n starrocks delete starrockscluster sr
# or
helm uninstall sr -n starrocks
```

PVCs are kept unless `persistentVolumeClaimRetentionPolicy.whenDeleted: Delete` is set on the component. Delete leftover PVCs by hand if you want the data gone. In shared-data mode, table data in S3 is not removed by deleting the cluster.

## Upstream sources

- [`deploy_starrocks_with_operator_howto.md`](../upstream/starrocks-kubernetes-operator/doc/deploy_starrocks_with_operator_howto.md)
- [`examples/starrocks/README.md`](../upstream/starrocks-kubernetes-operator/examples/starrocks/README.md)
- [`plan_cluster.md`](../upstream/starrocks/docs/en/deployment/preparation/plan_cluster.md)
- [`deploy_shared_data_manually.md`](../upstream/starrocks/docs/en/deployment/deploy_shared_data_manually.md)
- [`feature-support-shared-data.md`](../upstream/starrocks/docs/en/deployment/feature-support-shared-data.md)
- [`post_deployment_setup.md`](../upstream/starrocks/docs/en/deployment/manage_deployment/post_deployment_setup.md)
