# Helm values reference

A structured summary of the values in the StarRocks Helm charts at chart version 1.11.8. The commented source files are the authority:

- Cluster chart: [`charts/starrocks/values.yaml`](../../upstream/starrocks-kubernetes-operator/helm-charts/charts/kube-starrocks/charts/starrocks/values.yaml)
- Operator chart: [`charts/operator/values.yaml`](../../upstream/starrocks-kubernetes-operator/helm-charts/charts/kube-starrocks/charts/operator/values.yaml)
- Umbrella chart: [`kube-starrocks/values.yaml`](../../upstream/starrocks-kubernetes-operator/helm-charts/charts/kube-starrocks/values.yaml)
- Warehouse chart: [`warehouse/values.yaml`](../../upstream/starrocks-kubernetes-operator/helm-charts/charts/warehouse/values.yaml)

## Charts and nesting

| Chart | Top-level keys |
|---|---|
| `starrocks/operator` | `global`, `timeZone`, `nameOverride`, `starrocksOperator` |
| `starrocks/starrocks` | `nameOverride`, `initPassword`, `timeZone`, `datadog`, `metrics`, `starrocksCluster`, `starrocksFESpec`, `starrocksCnSpec`, `starrocksBeSpec`, `starrocksFeProxySpec`, `secrets`, `configMaps`, `resources` |
| `starrocks/kube-starrocks` | `operator:` (everything from the operator chart) and `starrocks:` (everything from the cluster chart) |
| `starrocks/warehouse` | `timeZone`, `datadog`, `spec`, `secrets`, `configMaps` |

Examples in this file use the `starrocks` chart layout. For `kube-starrocks`, indent everything under `starrocks:`.

## Key spelling: Helm versus CR

| Helm value | CR field |
|---|---|
| `starrocksFESpec` | `spec.starRocksFeSpec` |
| `starrocksBeSpec` | `spec.starRocksBeSpec` |
| `starrocksCnSpec` | `spec.starRocksCnSpec` |
| `starrocksFeProxySpec` | `spec.starRocksFeProxySpec` |
| `<component>.resources.requests` / `.limits` | `<component>.requests` / `.limits` |
| `<component>.image.repository` + `.tag` | `<component>.image` |
| `<component>.config` or `.configyaml` | `<component>.configMapInfo` plus a ConfigMap |
| `<component>.storageSpec` | `<component>.storageVolumes[]` |
| `<component>.emptyDirs`, `.hostPaths`, `.csiVolumes` | `<component>.storageVolumes[]` with a special `storageClassName` |
| `<component>.maxUnavailablePods` | `<component>.updateStrategy.rollingUpdate.maxUnavailable` |
| `<component>.entrypoint.script` | `<component>.command` and `.args` |
| `starrocksCluster.waitForFullRollout` | `spec.waitForFullRollout` |
| `starrocksCluster.disasterRecovery` | `spec.disasterRecovery` |

Some upstream how-to pages spell keys differently, for example `starrocksBESpec` or `starRocksFeProxySpec` in Helm snippets. The spellings above are the ones in `values.yaml`.

## Cluster chart: global sections

### `initPassword`

| Key | Default | Meaning |
|---|---|---|
| `enabled` | `false` | Set the `root` password with a Job at install |
| `isInstall` | `true` | Set to `false` after the first install when deploying with Argo CD |
| `password` | `""` | Plaintext password |
| `passwordSecret` | `""` | Name of a Secret with key `password`. Wins over `password`. |
| `image` | `""` | Job image. Defaults to the FE image. |
| `annotations`, `podAnnotations`, `resources` | empty | For the Job and its pod |

Takes effect on install only. Keep the block unchanged across upgrades.

### `timeZone`

Default `Asia/Shanghai`. Sets `TZ` in the pods.

### `datadog`

| Key | Default | Meaning |
|---|---|---|
| `log.enabled` | `false` | Add log collection annotations |
| `log.logConfig` | `'{}'` | Extra log config JSON. `source` and `service` are appended. |
| `log.enableMultilineLogParsing` | `false` | Add multi-line rules. FE uses a log4j timestamp pattern, BE and CN a glog pattern. |
| `metrics.enabled` | `false` | Add metrics scrape annotations |
| `profiling.fe`, `.be`, `.cn` | `false` | Enable profiling per component |
| `profiling.env` | `starrocks-default` | Value for `DD_ENV` |
| `profiling.configMode` | `service` | Datadog admission controller mode |

### `metrics.serviceMonitor`

| Key | Default | Meaning |
|---|---|---|
| `enabled` | `false` | Create a ServiceMonitor. Needs the Prometheus Operator. |
| `labels` | `{}` | Labels your Prometheus selects on |
| `interval` | `15s` | Scrape interval |
| `basicAuth.enabled` | `false` | With `usernameSecretName`, `usernameSecretKey`, `passwordSecretName`, `passwordSecretKey` |
| `endpointParam.enabled` | `false` | With `params`, for example `with_materialized_view_metrics: ["all"]` |

### `starrocksCluster`

| Key | Default | Meaning |
|---|---|---|
| `name` | `""` | Cluster name. Falls back to `nameOverride`, which is `kube-starrocks`. |
| `namespace` | `""` | Falls back to the release namespace |
| `annotations` | `{}` | Annotations on the `StarRocksCluster` |
| `enabledBe` | `true` | Deploy BE |
| `enabledCn` | `false` | Deploy CN |
| `waitForFullRollout` | `false` | Finish the FE rollout before updating BE and CN |
| `disasterRecovery.enabled`, `.generation` | unset | Shared-data restore |
| `componentValues` | see below | Defaults shared by FE, BE and CN |

`componentValues` holds `image.tag`, `hostAliases`, `runAsNonRoot`, `schedulerName`, `serviceAccount`, `imagePullSecrets`, `tolerations`, `topologySpreadConstraints`, `nodeSelector`, `affinity` and `podLabels`. A value set on a component **replaces** the shared one. Lists and maps are not merged.

### Top-level helpers

| Key | Meaning |
|---|---|
| `secrets[]` | Secrets the chart should create: `name`, `data` |
| `configMaps[]` | ConfigMaps the chart should create: `name`, `data` |
| `resources[]` | Any other Kubernetes objects to create with the release, for example a ServiceAccount |

## Cluster chart: component sections

`starrocksFESpec`, `starrocksBeSpec` and `starrocksCnSpec` share almost all keys.

### Identity and scheduling

| Key | Default | Notes |
|---|---|---|
| `replicas` | FE 1, BE 1 | Omit on CN when autoscaling |
| `image.repository`, `image.tag` | `starrocks/<fe|be|cn>-ubuntu`, tag from `componentValues` | |
| `imagePullPolicy` | `IfNotPresent` | |
| `imagePullSecrets` | `[]` | |
| `serviceAccount` | `""` | |
| `annotations` | `{}` | Pod annotations |
| `podLabels` | `{}` | |
| `nodeSelector`, `affinity`, `tolerations`, `topologySpreadConstraints`, `schedulerName` | empty | |
| `hostAliases` | `[]` | |

### Security

| Key | Default |
|---|---|
| `runAsNonRoot` | `false` |
| `readOnlyRootFilesystem` | `false` |
| `capabilities` | `{}` |
| `sysctls` | `[]` |

### Service

| Key | Default | Notes |
|---|---|---|
| `service.type` | `ClusterIP` | `ClusterIP`, `NodePort` or `LoadBalancer` |
| `service.loadbalancerIP` | `""` | Note the lowercase `b` in the Helm key |
| `service.annotations`, `service.labels` | `{}` | |
| `service.ports` | `[]` | Entries with `name` or `containerPort`, plus `port` and `nodePort`. FE names: `http`, `query`, `rpc`, `edit-log`. |
| `service.loadBalancerSourceRanges` | `[]` | |
| `service.externalTrafficPolicy` | `""` | `Cluster` or `Local` |

### Resources

| Component | Default requests | Default limits |
|---|---|---|
| FE | 4 CPU, 4Gi | 8 CPU, 8Gi |
| CN | 4 CPU, 8Gi | 8 CPU, 8Gi |

Set a limit to `"unlimited"` to remove it. The defaults are far below production sizing.

### Storage: `storageSpec`

| Key | FE default | BE and CN default | Meaning |
|---|---|---|---|
| `name` | `""` | `""` | Volume name prefix. Empty means `emptyDir`. Required for persistence. |
| `storageClassName` | `""` | `""` | Empty uses the default class. `hostPath` is not allowed here. |
| `storageSize` | `10Gi` | `1Ti` | Metadata volume for FE. Each data volume for BE and CN. |
| `storageCount` | | `1` | Number of data volumes |
| `storageMountPath` | `""` | `""` | Defaults to `/opt/starrocks/fe/meta`, `/opt/starrocks/be/storage`, `/opt/starrocks/cn/storage`. With `storageCount` above 1 it is a prefix: `storage0`, `storage1`. |
| `logStorageClassName` | `""` | `""` | Defaults to `storageClassName` |
| `logStorageSize` | `5Gi` | `20Gi` | `0Gi` disables the log PVC |
| `logMountPath` | `""` | `""` | Defaults to `/opt/starrocks/<component>/log` |
| `spillStorageClassName` | | `""` | Defaults to `storageClassName` |
| `spillStorageSize` | | `0Gi` | Above 0 creates a spill PVC. Add `spill_local_storage_dir` to the config. |
| `spillMountPath` | | `""` | Defaults to `/opt/starrocks/<be|cn>/spill` |

These fields cannot be changed after install. Changing a mount path away from its default needs the matching config setting.

Other volume lists:

| Key | Entry shape |
|---|---|
| `emptyDirs[]` | `name`, `mountPath` |
| `hostPaths[]` | `name`, `hostPath.path`, `hostPath.type`, `mountPath` |
| `csiVolumes[]` | `name`, `mountPath`, `readOnly`, `csi.driver`, `csi.readOnly` |
| `persistentVolumeClaimRetentionPolicy` | `whenDeleted` on all components. `whenScaled` on CN only. |

### Configuration

| Key | Meaning |
|---|---|
| `config` | Inline `fe.conf`, `be.conf` or `cn.conf` |
| `configyaml` | Map form. When non-empty it replaces `config`. Quote numbers. |
| `feEnvVars`, `beEnvVars`, `cnEnvVars` | Environment variables |
| `secrets[]`, `configMaps[]` | Extra mounts: `name`, `mountPath`, `subPath` |
| `entrypoint.script` | Custom entrypoint script |

Chart default `fe.conf`:

```
LOG_DIR = ${STARROCKS_HOME}/log
DATE = "$(date +%Y%m%d-%H%M%S)"
JAVA_OPTS="-Dlog4j2.formatMsgNoLookups=true -Xmx8192m -XX:+UseG1GC -Xlog:gc*:${LOG_DIR}/fe.gc.log.$DATE:time"
http_port = 8030
rpc_port = 9020
query_port = 9030
edit_log_port = 9010
mysql_service_nio_enabled = true
sys_log_level = INFO
min_graceful_exit_time_second = 25
```

Chart default `cn.conf`:

```
sys_log_level = INFO
thrift_port = 9060
webserver_port = 8040
heartbeat_service_port = 9050
brpc_port = 8060
```

### Lifecycle

| Key | Default | Meaning |
|---|---|---|
| `terminationGracePeriodSeconds` | `120` | |
| `startupProbeFailureSeconds` | unset (300) | |
| `livenessProbeFailureSeconds` | unset (15) | |
| `readinessProbeFailureSeconds` | unset (15) | |
| `minReadySeconds` | `0` | |
| `podManagementPolicy` | `Parallel` | |
| `maxUnavailablePods` | unset (1) | Cannot be 0. Needs the `MaxUnavailableStatefulSet` feature gate. |
| `lifecycle` | `{}` | Replaces the operator's `preStop` hook |
| `sidecars[]` | `[]` | Extra containers |
| `sidecarsMap` | `{}` | Map form keyed by container name. Wins over `sidecars`. |
| `initContainers[]` | `[]` | |
| `shareProcessNamespace` | unset | |

Sidecars can mount the component's volumes by name. The names are the `storageSpec.name` prefix plus `-meta`, `-data` or `-log`.

### CN only: `autoScalingPolicy`

| Key | Meaning |
|---|---|
| `version` | HPA API version. The chart comment gives `v2beta2` as the default. |
| `minReplicas`, `maxReplicas` | Bounds |
| `hpaPolicy.metrics` | Standard HPA metrics |
| `hpaPolicy.behavior` | Standard HPA behavior |

Needs `starrocksCluster.enabledCn: true`.

## Cluster chart: `starrocksFeProxySpec`

| Key | Default | Meaning |
|---|---|---|
| `enabled` | `false` | Deploy the FE proxy |
| `replicas` | `1` | |
| `image.repository`, `image.tag` | empty (`nginx:1.24.0`) | |
| `imagePullPolicy` | `IfNotPresent` | |
| `resources` | 1 CPU, 2Gi | |
| `resolver` | `""` (`kube-dns.kube-system.svc.cluster.local`) | DNS resolver for nginx |
| `service.type` | `ClusterIP` | |
| `service.ports` | | Port name `http-port`, container port 8080 |
| `service.loadbalancerIP`, `.annotations`, `.labels` | empty | |
| `imagePullSecrets`, `nodeSelector`, `affinity`, `tolerations`, `podLabels`, `emptyDirs` | empty | |
| `livenessProbeFailureSeconds`, `readinessProbeFailureSeconds` | unset | |

## Warehouse chart

| Key | Meaning |
|---|---|
| `nameOverride` | Warehouse name |
| `spec.starRocksClusterName` | Cluster to attach to, in the same namespace |
| `spec.replicas` | CN count. Omit when autoscaling. |
| `spec.image.repository`, `spec.image.tag` | Enterprise CN image |
| `spec.resources` | Requests and limits |
| `spec.envVars` | Environment variables |
| `spec.config` | `cn.conf` |
| `spec.storageSpec` | `storageSize`, `logStorageSize` and related keys |
| `spec.persistentVolumeClaimRetentionPolicy` | `whenDeleted`, `whenScaled` |
| `spec.autoScalingPolicy` | Same shape as on CN |
| `spec.service`, `spec.serviceAccount`, `spec.annotations`, `spec.podLabels`, scheduling keys, `spec.runAsNonRoot`, `spec.hostAliases`, `spec.minReadySeconds` | As on CN |
| `spec.secrets`, `spec.configMaps` | Extra mounts |
| `secrets`, `configMaps` | Objects for the chart to create |
| `timeZone`, `datadog` | As in the cluster chart |

## Operator chart

See the table in [Install the operator](../02-install-operator.md#operator-chart-values).

## Useful Helm commands

```bash
helm show values starrocks/starrocks > values.yaml       # full default values
helm template sr starrocks/starrocks -f my-values.yaml   # render without installing
helm diff upgrade sr starrocks/starrocks -f my-values.yaml   # needs the helm-diff plugin
helm get values sr -n starrocks                          # values of a release
```
