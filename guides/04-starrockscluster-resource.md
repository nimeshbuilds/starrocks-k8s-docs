# 4. The StarRocksCluster resource

A field-by-field guide to the `StarRocksCluster` spec, grouped by what you are trying to do. For the raw generated reference see the [CRD API reference](reference/crd-api-reference.md). For the Helm spelling of each field see the [Helm values reference](reference/helm-values-reference.md).

## Shape

```yaml
apiVersion: starrocks.com/v1
kind: StarRocksCluster
metadata:
  name: <cluster-name>
  namespace: <namespace>
spec:
  serviceAccount: <deprecated, set it per component>
  waitForFullRollout: false
  disasterRecovery: {enabled: false, generation: 1}
  starRocksFeSpec: {...}        # required
  starRocksBeSpec: {...}        # optional
  starRocksCnSpec: {...}        # optional
  starRocksFeProxySpec: {...}   # optional
status:
  phase: running | failed | reconciling
  starRocksFeStatus: {...}
  starRocksBeStatus: {...}
  starRocksCnStatus: {...}
  starRocksFeProxyStatus: {...}
```

## Top-level fields

| Field | Meaning |
|---|---|
| `starRocksFeSpec` | FE component. Required. |
| `starRocksBeSpec` | BE component. Omit for a pure shared-data cluster. |
| `starRocksCnSpec` | CN component. |
| `starRocksFeProxySpec` | FE proxy for Stream Load from outside the cluster network. |
| `serviceAccount` | Deprecated at this level. Set `serviceAccount` inside each component. |
| `waitForFullRollout` | When `true`, the operator waits for every FE replica to be ready on the new revision before it updates BE and CN. Default `false`, in which case BE and CN updates may proceed once any FE pod is ready. Turn it on to stop a bad FE rollout from spreading. |
| `disasterRecovery` | `enabled` and `generation`. Starts a shared-data restore from a cluster snapshot. See [Disaster recovery](14-disaster-recovery.md). |

## Fields shared by FE, BE and CN

All three components embed the same two structures, so these fields work on each.

### Image and replicas

| Field | Meaning |
|---|---|
| `image` | Container image, for example `starrocks/fe-ubuntu:<version>` |
| `imagePullPolicy` | Standard Kubernetes pull policy |
| `imagePullSecrets` | Secrets for a private registry |
| `replicas` | Desired pod count. On CN, leave it unset when `autoScalingPolicy` is set. If both are set, every apply resets the StatefulSet to `replicas` and wipes what the autoscaler chose. |

### Resources

`requests` and `limits` sit directly on the component spec, not under a `resources:` key:

```yaml
starRocksCnSpec:
  requests: {cpu: 16, memory: 64Gi}
  limits:   {cpu: 16, memory: 64Gi}
```

The Helm chart does use a `resources:` wrapper, and accepts `"unlimited"` to drop a single limit.

### Configuration

| Field | Meaning |
|---|---|
| `configMapInfo.configMapName` | ConfigMap holding the component's config file |
| `configMapInfo.resolveKey` | Key in that ConfigMap: `fe.conf`, `be.conf` or `cn.conf` |
| `feEnvVars`, `beEnvVars`, `cnEnvVars` | Environment variables for the main container. Standard `env` entries, including `valueFrom`. |
| `configMaps` | Extra ConfigMaps to mount: `name`, `mountPath`, optional `subPath` |
| `secrets` | Extra Secrets to mount, same shape |
| `command`, `args` | Override the container entrypoint |

Details in [Configuration](05-configuration.md).

### Storage

| Field | Meaning |
|---|---|
| `storageVolumes[].name` | Volume name. Becomes the PVC name prefix. |
| `storageVolumes[].storageClassName` | A real StorageClass, or one of the special values `emptyDir`, `hostPath`, `csi`. Empty means the cluster default class. |
| `storageVolumes[].storageSize` | Size such as `100Gi`. Ignored for `emptyDir` and `hostPath`. |
| `storageVolumes[].mountPath` | Where to mount it |
| `storageVolumes[].subPath`, `.readOnly` | Standard mount options |
| `storageVolumes[].hostPath` | Required when `storageClassName: hostPath` |
| `storageVolumes[].csi` | A Kubernetes `CSIVolumeSource` for an ephemeral inline volume |
| `persistentVolumeClaimRetentionPolicy` | `whenDeleted` works on every component. `whenScaled` works on CN only. |

Details in [Storage](06-storage.md).

### Scheduling

| Field | Meaning |
|---|---|
| `nodeSelector` | Node labels to require |
| `affinity` | Node and pod affinity or anti-affinity |
| `tolerations` | Taints to tolerate |
| `topologySpreadConstraints` | Spread across zones or nodes |
| `schedulerName` | Use a non-default scheduler |
| `podLabels` | Extra labels on pods |
| `annotations` | Annotations on pods, for example for metrics scraping |

Spread FE pods across nodes with required pod anti-affinity on `app.kubernetes.io/component: fe`, so one node failure cannot take out the quorum.

### Service

| Field | Meaning |
|---|---|
| `service.type` | `ClusterIP`, `NodePort` or `LoadBalancer` |
| `service.annotations`, `service.labels` | Applied to the client-facing service only, not the headless one |
| `service.ports[]` | Override a port: `name`, `port`, `containerPort`, `nodePort`. FE port names are `http`, `query`, `rpc`, `edit-log`. |
| `service.loadBalancerIP` | Static IP for a LoadBalancer |
| `service.loadBalancerSourceRanges` | Client CIDRs allowed through the load balancer |
| `service.externalTrafficPolicy` | `Cluster` or `Local` |

Details in [Networking and access](08-networking-and-access.md).

### Security context

| Field | Meaning |
|---|---|
| `runAsNonRoot` | When `true`, the operator sets user and group ID 1000. Choose this at install time. Files created by root earlier will not be writable later. |
| `readOnlyRootFilesystem` | Needs extra volumes and an entrypoint change. See [Storage](06-storage.md#read-only-root-filesystem). |
| `capabilities` | Linux capabilities to add or drop |
| `sysctls` | Namespaced sysctls for the pod |
| `serviceAccount` | ServiceAccount for the component's pods. This is how pods get cloud IAM permissions. |
| `hostAliases` | Extra `/etc/hosts` entries |
| `shareProcessNamespace` | Share the PID namespace with sidecars |

### Lifecycle and rollout

| Field | Default | Meaning |
|---|---|---|
| `startupProbeFailureSeconds` | 300 | Total time allowed for startup. `0` disables the probe. |
| `livenessProbeFailureSeconds` | 15 | Total unresponsive time before a restart. `0` disables. |
| `readinessProbeFailureSeconds` | 15 | Total unresponsive time before the pod is marked not ready. `0` disables. |
| `terminationGracePeriodSeconds` | Kubernetes default in the CR, 120 in the Helm chart | Time allowed for graceful shutdown |
| `lifecycle` | operator-supplied `preStop` | The operator adds a `preStop` hook per component: `/opt/starrocks/fe_prestop.sh`, `be_prestop.sh`, `cn_prestop.sh`. Setting this replaces it. |
| `updateStrategy` | rolling update | StatefulSet update strategy. `maxUnavailable` needs the `MaxUnavailableStatefulSet` feature gate. |
| `podManagementPolicy` | `Parallel` | Differs from the StatefulSet default of `OrderedReady` |
| `minReadySeconds` | 0 | How long a new pod must stay ready before it counts as available |
| `sidecars`, `initContainers` | none | Extra containers |

Probe values are totals. The probe period is 5 seconds, and the failure threshold is the total divided by 5, rounded up.

## CN-only: `autoScalingPolicy`

```yaml
starRocksCnSpec:
  autoScalingPolicy:
    version: v2            # v1, v2beta2 or v2
    minReplicas: 1
    maxReplicas: 10
    hpaPolicy:
      metrics: [...]       # standard HPA metric specs
      behavior: {...}      # standard HPA behavior
```

The operator creates an HPA named `<cluster>-cn-autoscaler`. See [Scaling and autoscaling](07-scaling-and-autoscaling.md).

## FE proxy: `starRocksFeProxySpec`

Supports `replicas`, `requests`, `limits`, `image`, `service`, scheduling fields and probe timeouts, plus:

| Field | Meaning |
|---|---|
| `resolver` | DNS resolver for nginx. Default `kube-dns.kube-system.svc.cluster.local`. Change it if your cluster DNS service has another name. |

It embeds only the generic workload fields, so component-only fields such as `configMaps`, `sidecars` and `runAsNonRoot` are not available on the proxy.

## Status

```bash
kubectl -n starrocks get starrockscluster <name> -o yaml
```

| Field | Meaning |
|---|---|
| `status.phase` | `running`, `failed` or `reconciling` |
| `status.reason` | Error text from a sub-controller |
| `status.starRocksFeStatus`, `...BeStatus`, `...CnStatus`, `...FeProxyStatus` | Per-component phase, service name, and lists of running, creating and failed instances |
| `status.disasterRecoveryStatus` | `phase` (`todo`, `doing`, `done`), `reason`, `observedGeneration` |

## The StarRocksWarehouse resource

```yaml
apiVersion: starrocks.com/v1
kind: StarRocksWarehouse
metadata:
  name: wh1                    # dashes become underscores in the SQL warehouse name
spec:
  starRocksCluster: <cluster>  # must be in the same namespace
  template:                    # same fields as a CN spec
    image: <enterprise CN image>
    replicas: 1
    requests: {cpu: 8, memory: 8Gi}
    limits:   {cpu: 8, memory: 8Gi}
    envVars: []                # note: envVars here, not cnEnvVars
    autoScalingPolicy: {...}
```

Upstream documents warehouses as an enterprise feature that needs an enterprise CN image. Check your edition before planning around them. See [Scaling and autoscaling](07-scaling-and-autoscaling.md#warehouses).

## Editing a live cluster

- `kubectl apply -f`, `kubectl patch`, `kubectl edit src <name>` and `helm upgrade` all work. Keep one source of truth.
- Most pod-template changes trigger a rolling restart of that component.
- Volume fields cannot be changed after install.
- If the object is too large for `kubectl apply`, use `kubectl replace -f`.

## Upstream sources

- [`doc/api.md`](../upstream/starrocks-kubernetes-operator/doc/api.md)
- [`deploy_a_starrocks_cluster_with_all_features.yaml`](../upstream/starrocks-kubernetes-operator/examples/starrocks/deploy_a_starrocks_cluster_with_all_features.yaml)
- [`deploy/starrocks.com_starrocksclusters.yaml`](../upstream/starrocks-kubernetes-operator/deploy/starrocks.com_starrocksclusters.yaml)
- [`deploy_warehouse_howto.md`](../upstream/starrocks-kubernetes-operator/doc/deploy_warehouse_howto.md)
