# CRD API reference (Markdown)

This page is a plain-Markdown rendering of the operator's generated API reference, which upstream publishes as HTML inside a `.md` file. The content is the same. Only the format changed, so it is easier to search and easier for tools to read.

- Source: [`upstream/starrocks-kubernetes-operator/doc/api.md`](../../upstream/starrocks-kubernetes-operator/doc/api.md)
- API group and version: `starrocks.com/v1`
- Kinds: `StarRocksCluster` and `StarRocksWarehouse`
- The authoritative schema is the CRD itself: [`deploy/starrocks.com_starrocksclusters.yaml`](../../upstream/starrocks-kubernetes-operator/deploy/starrocks.com_starrocksclusters.yaml) and [`deploy/starrocks.com_starrockswarehouses.yaml`](../../upstream/starrocks-kubernetes-operator/deploy/starrocks.com_starrockswarehouses.yaml)

For a task-oriented view of the same fields, see [The StarRocksCluster resource](../04-starrockscluster-resource.md).

## Types

[AnnotationOperationValue](#annotationoperationvalue), [AutoScalerVersion](#autoscalerversion), [AutoScalingPolicy](#autoscalingpolicy), [ComponentPhase](#componentphase), [ConfigMapInfo](#configmapinfo), [ConfigMapReference](#configmapreference), [DRPhase](#drphase), [DisasterRecovery](#disasterrecovery), [DisasterRecoveryStatus](#disasterrecoverystatus), [HPAPolicy](#hpapolicy), [HorizontalScaler](#horizontalscaler), [MountInfo](#mountinfo), [Phase](#phase), [SecretReference](#secretreference), [SpecInterface](#specinterface), [StarRocksBeSpec](#starrocksbespec), [StarRocksBeStatus](#starrocksbestatus), [StarRocksCluster](#starrockscluster), [StarRocksClusterSpec](#starrocksclusterspec), [StarRocksClusterStatus](#starrocksclusterstatus), [StarRocksCnSpec](#starrockscnspec), [StarRocksCnStatus](#starrockscnstatus), [StarRocksComponentSpec](#starrockscomponentspec), [StarRocksComponentStatus](#starrockscomponentstatus), [StarRocksFeProxySpec](#starrocksfeproxyspec), [StarRocksFeProxyStatus](#starrocksfeproxystatus), [StarRocksFeSpec](#starrocksfespec), [StarRocksFeStatus](#starrocksfestatus), [StarRocksLoadSpec](#starrocksloadspec), [StarRocksProbe](#starrocksprobe), [StarRocksService](#starrocksservice), [StarRocksServicePort](#starrocksserviceport), [StarRocksWarehouse](#starrockswarehouse), [StarRocksWarehouseSpec](#starrockswarehousespec), [StarRocksWarehouseStatus](#starrockswarehousestatus), [StorageVolume](#storagevolume), [WarehouseComponentSpec](#warehousecomponentspec)

## AnnotationOperationValue

Type: `string` alias.

AnnotationOperationValue present the operation for fe, cn, be.

## AutoScalerVersion

Type: `string` alias.

Appears on: AutoScalingPolicy, HorizontalScaler

| Value | Description |
|---|---|
| `v1` | AutoScalerV1 the cn service use v1 autoscaler. Reference to https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/ |
| `v2` | AutoScalerV2 the cn service use v2. Reference to https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/ |
| `v2beta2` | AutoScalerV2Beta2 the cn service use v2beta2. Reference to https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/ |

## AutoScalingPolicy

Appears on: StarRocksCnSpec, WarehouseComponentSpec

AutoScalingPolicy defines the auto scale

| Field | Type | Description |
|---|---|---|
| `hpaPolicy` | HPAPolicy | the policy of autoscaling. operator use autoscaling v2. |
| `version` | AutoScalerVersion | (Optional) version represents the autoscaler version for cn service. only support v1,v2beta2,v2 |
| `minReplicas` | int32 | (Optional) MinReplicas is the lower limit for the number of replicas to which the autoscaler can scale down. It defaults to 1 pod. |
| `maxReplicas` | int32 | MaxReplicas is the upper limit for the number of pods that can be set by the autoscaler; cannot be smaller than MinReplicas. |

## ComponentPhase

Type: `string` alias.

Appears on: StarRocksComponentStatus

ComponentPhase represent the component phase. e.g. 1. StarRocksCluster contains three components: FE, CN, BE. 2. StarRocksWarehouse reuse the CN component. The possible value for component phase are: reconciling, failed, running.

| Value | Description |
|---|---|
| `failed` | ComponentFailed the pod of component is failed |
| `reconciling` | ComponentReconciling the starrocks component is reconciling |
| `running` | ComponentRunning all components runs available. |

## ConfigMapInfo

Appears on: StarRocksLoadSpec

| Field | Type | Description |
|---|---|---|
| `configMapName` | string | the config info for start progress. |
| `resolveKey` | string | the config response key in configmap. |

## ConfigMapReference

Appears on: StarRocksComponentSpec

| Field | Type | Description |
|---|---|---|
| `name` | string | This must match the Name of a ConfigMap or Secret in the same namespace, and the length of name must not more than 50 characters. |
| `mountPath` | string | Path within the container at which the volume should be mounted. Must not contain ‘:’. |
| `subPath` | string | (Optional) SubPath within the volume from which the container’s volume should be mounted. Defaults to “” (volume’s root). |

## DRPhase

Type: `string` alias.

Appears on: DisasterRecoveryStatus

| Value | Description |
|---|---|
| `doing` |  |
| `done` |  |
| `todo` |  |

## DisasterRecovery

Appears on: StarRocksClusterSpec

DisasterRecovery is used to determine whether to enter disaster recovery mode.

| Field | Type | Description |
|---|---|---|
| `enabled` | bool | Enabled is used to determine whether to enter disaster recovery mode. |
| `generation` | int64 | Generation records the generation of disaster recovery. If you want to trigger disaster recovery, you should increase the generation. |

## DisasterRecoveryStatus

Appears on: StarRocksClusterStatus

DisasterRecoveryStatus represents the status of disaster recovery. Note: you should create a new instance of DisasterRecoveryStatus by NewDisasterRecoveryStatus.

| Field | Type | Description |
|---|---|---|
| `phase` | DRPhase | the available phase include: todo, doing, done |
| `reason` | string | the reason of disaster recovery. |
| `startTimestamp` | int64 | the unix time of starting disaster recovery. |
| `endTimestamp` | int64 | the unix time of ending disaster recovery. |
| `observedGeneration` | int64 | the observed generation of disaster recovery. If the observed generation is less than the generation, it will trigger disaster recovery. |

## HPAPolicy

Appears on: AutoScalingPolicy

| Field | Type | Description |
|---|---|---|
| `metrics` | []Kubernetes autoscaling/v2beta2.MetricSpec | (Optional) Metrics specifies how to scale based on a single metric the struct copy from k8s.io/api/autoscaling/v2beta2/types.go. the redundancy code will hide the restriction about HorizontalPodAutoscaler version and kubernetes releases matching issue. the splice will have unsafe.Pointer convert, so be careful to edit the struct fields. |
| `behavior` | Kubernetes autoscaling/v2beta2.HorizontalPodAutoscalerBehavior | (Optional) HorizontalPodAutoscalerBehavior configures the scaling behavior of the target. the struct copy from k8s.io/api/autoscaling/v2beta2/types.go. the redundancy code will hide the restriction about HorizontalPodAutoscaler version and kubernetes releases matching issue. the |

## HorizontalScaler

Appears on: StarRocksCnStatus

| Field | Type | Description |
|---|---|---|
| `name` | string | the horizontal scaler name |
| `version` | AutoScalerVersion | the horizontal version. |

## MountInfo

MountInfo The reason why we do not support defaultMode is that we use hash.HashObject to calculate the actual volume name. This volume name is used in pod template of statefulset, and if this MountInfo type has been changed, the volume name will be changed too, and that will make pods restart. The default mode is 0644, and in order to support to set permission information for a configMap or secret, we add should specify the subPath and specify a command or args in the container. And It will be set 0755.

| Field | Type | Description |
|---|---|---|
| `name` | string | This must match the Name of a ConfigMap or Secret in the same namespace, and the length of name must not more than 50 characters. |
| `mountPath` | string | Path within the container at which the volume should be mounted. Must not contain ‘:’. |
| `subPath` | string | (Optional) SubPath within the volume from which the container’s volume should be mounted. Defaults to “” (volume’s root). |

## Phase

Type: `string` alias.

Appears on: StarRocksClusterStatus

Phase is defined under status, e.g. 1. StarRocksClusterStatus.Phase represents the phase of starrocks cluster. 2. StarRocksWarehouseStatus.Phase represents the phase of starrocks warehouse. The possible value for cluster phase are: running, failed, pending, deleting.

| Value | Description |
|---|---|
| `failed` | ClusterFailed represents starrocks cluster failed. |
| `reconciling` | ClusterReconciling represents some component is reconciling |
| `running` | ClusterRunning represents starrocks cluster is running. |

## SecretReference

Appears on: StarRocksComponentSpec

| Field | Type | Description |
|---|---|---|
| `name` | string | This must match the Name of a ConfigMap or Secret in the same namespace, and the length of name must not more than 50 characters. |
| `mountPath` | string | Path within the container at which the volume should be mounted. Must not contain ‘:’. |
| `subPath` | string | (Optional) SubPath within the volume from which the container’s volume should be mounted. Defaults to “” (volume’s root). |

## SpecInterface

SpecInterface defines the common interface that must be implemented by all StarRocks component specs (FE, BE, CN, FE Proxy). It provides methods to configure pod and container settings like security context, lifecycle hooks, networking, and storage. All components including StarRocksFeSpec, StarRocksBeSpec, StarRocksCnSpec, StarRocksFeProxySpec have implemented the SpecInterface. If a method has the same implementation, we will implement in StarRocksLoadSpec which implements the loadInterface interface.

## StarRocksBeSpec

Appears on: StarRocksClusterSpec

StarRocksBeSpec defines the desired state of be.

| Field | Type | Description |
|---|---|---|
| `StarRocksComponentSpec` | StarRocksComponentSpec | (Members of `StarRocksComponentSpec` are embedded into this type.) |
| `beEnvVars` | []Kubernetes core/v1.EnvVar | (Optional) beEnvVars is a slice of environment variables that are added to the pods, the default is empty. |

## StarRocksBeStatus

Appears on: StarRocksClusterStatus

StarRocksBeStatus represents the status of starrocks be.

| Field | Type | Description |
|---|---|---|
| `StarRocksComponentStatus` | StarRocksComponentStatus | (Members of `StarRocksComponentStatus` are embedded into this type.) |

## StarRocksCluster

StarRocksCluster defines a starrocks cluster deployment.

| Field | Type | Description |
|---|---|---|
| `metadata` | Kubernetes meta/v1.ObjectMeta | Refer to the Kubernetes API documentation for the fields of the `metadata` field. |
| `spec` | StarRocksClusterSpec | Specification of the desired state of the starrocks cluster. `serviceAccount` string |
| `starRocksFeSpec` | StarRocksFeSpec | StarRocksFeSpec define fe configuration for start fe service. |
| `starRocksBeSpec` | StarRocksBeSpec | StarRocksBeSpec define be configuration for start be service. |
| `starRocksCnSpec` | StarRocksCnSpec | StarRocksCnSpec define cn configuration for start cn service. |
| `starRocksFeProxySpec` | StarRocksFeProxySpec | StarRocksLoadSpec define a proxy for fe. |
| `disasterRecovery` | DisasterRecovery | (Optional) DisasterRecovery is used to determine whether to enter disaster recovery mode. |
| `waitForFullRollout` | bool | (Optional) WaitForFullRollout controls rolling upgrade behavior. When set to true, the operator will wait for FE StatefulSet to be fully rolled out (all replicas ready and at the same revision) before updating BE/CN components. This prevents cascading failures if a bad FE version is deployed. When false (default), BE/CN updates can proceed as soon as any FE pod is ready. Defaults to false for backward compatibility. |

## StarRocksClusterSpec

Appears on: StarRocksCluster

StarRocksClusterSpec defines the desired state of StarRocksCluster

| Field | Type | Description |
|---|---|---|
| `serviceAccount` | string | (Optional) Specify a Service Account for starRocksCluster use k8s cluster. Deprecated: component use serviceAccount in own’s field. |
| `starRocksFeSpec` | StarRocksFeSpec | StarRocksFeSpec define fe configuration for start fe service. |
| `starRocksBeSpec` | StarRocksBeSpec | StarRocksBeSpec define be configuration for start be service. |
| `starRocksCnSpec` | StarRocksCnSpec | StarRocksCnSpec define cn configuration for start cn service. |
| `starRocksFeProxySpec` | StarRocksFeProxySpec | StarRocksLoadSpec define a proxy for fe. |
| `disasterRecovery` | DisasterRecovery | (Optional) DisasterRecovery is used to determine whether to enter disaster recovery mode. |
| `waitForFullRollout` | bool | (Optional) WaitForFullRollout controls rolling upgrade behavior. When set to true, the operator will wait for FE StatefulSet to be fully rolled out (all replicas ready and at the same revision) before updating BE/CN components. This prevents cascading failures if a bad FE version is deployed. When false (default), BE/CN updates can proceed as soon as any FE pod is ready. Defaults to false for backward compatibility. |

## StarRocksClusterStatus

Appears on: StarRocksCluster

StarRocksClusterStatus defines the observed state of StarRocksCluster.

| Field | Type | Description |
|---|---|---|
| `phase` | Phase | Represents the state of cluster. the possible value are: running, failed, pending |
| `reason` | string | Reason represents the errors when calling sub-controllers |
| `starRocksFeStatus` | StarRocksFeStatus | Represents the status of fe. the status have running, failed and creating pods. |
| `starRocksBeStatus` | StarRocksBeStatus | Represents the status of be. the status have running, failed and creating pods. |
| `starRocksCnStatus` | StarRocksCnStatus | Represents the status of cn. the status have running, failed and creating pods. |
| `starRocksFeProxyStatus` | StarRocksFeProxyStatus | Represents the status of fe proxy. the status have running, failed and creating pods. |
| `disasterRecoveryStatus` | DisasterRecoveryStatus | (Optional) DisasterRecoveryStatus represents the status of disaster recovery. |

## StarRocksCnSpec

Appears on: StarRocksClusterSpec

StarRocksCnSpec defines the desired state of cn.

| Field | Type | Description |
|---|---|---|
| `StarRocksComponentSpec` | StarRocksComponentSpec | (Members of `StarRocksComponentSpec` are embedded into this type.) |
| `cnEnvVars` | []Kubernetes core/v1.EnvVar | (Optional) cnEnvVars is a slice of environment variables that are added to the pods, the default is empty. |
| `autoScalingPolicy` | AutoScalingPolicy | AutoScalingPolicy auto scaling strategy |

## StarRocksCnStatus

Appears on: StarRocksClusterStatus, StarRocksWarehouseStatus

WarehouseComponentStatus represents the status of component.

| Field | Type | Description |
|---|---|---|
| `StarRocksComponentStatus` | StarRocksComponentStatus | (Members of `StarRocksComponentStatus` are embedded into this type.) |
| `hpaName` | string | The policy name of autoScale. Deprecated |
| `horizontalScaler` | HorizontalScaler | HorizontalAutoscaler have the autoscaler information. |
| `replicas` | int32 | Replicas is the total number of non-terminated CN pods targeted. |
| `selector` | string | Selector for CN pods. The HPA will use this selector to know which pods to monitor. |

## StarRocksComponentSpec

Appears on: StarRocksBeSpec, StarRocksCnSpec, StarRocksFeSpec, WarehouseComponentSpec

StarRocksComponentSpec defines the shared specification for all StarRocks components except FE Proxy

| Field | Type | Description |
|---|---|---|
| `StarRocksLoadSpec` | StarRocksLoadSpec | (Members of `StarRocksLoadSpec` are embedded into this type.) |
| `runAsNonRoot` | bool | RunAsNonRoot is used to determine whether to run starrocks as a normal user. If RunAsNonRoot is true, operator will set RunAsUser and RunAsGroup to 1000 in securityContext. default: nil |
| `capabilities` | Kubernetes core/v1.Capabilities | (Optional) refer to https://kubernetes.io/docs/tasks/configure-pod-container/security-context/#set-capabilities-for-a-container grant certain privileges to a process without granting all the privileges of the root user |
| `configMaps` | []ConfigMapReference | (Optional) the reference for configMap which allow users to mount any files to container. |
| `secrets` | []SecretReference | (Optional) the reference for secrets. |
| `hostAliases` | []Kubernetes core/v1.HostAlias | (Optional) HostAliases is an optional list of hosts and IPs that will be injected into the pod’s hosts file if specified. This is only valid for non-hostNetwork pods. |
| `terminationGracePeriodSeconds` | int64 | (Optional) TerminationGracePeriodSeconds defines duration in seconds the pod needs to terminate gracefully. May be decreased in delete request. Value must be non-negative integer. The value zero indicates stop immediately via the kill signal (no opportunity to shut down). If this value is nil, the default grace period will be used instead. The grace period is the duration in seconds after the processes running in the pod are sent a termination signal and the time when the processes are forcibly halted with a kill signal. Set this value longer than the expected cleanup time for your process. Defaults to 120 seconds. |
| `sidecars` | []Kubernetes core/v1.Container | (Optional) Sidecars is an optional list of containers that are run in the same pod as the starrocks component. You can use this field to launch helper containers that provide additional functionality to the main container. See https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/pod-v1/#Container for how to configure a container. |
| `initContainers` | []Kubernetes core/v1.Container | InitContainers is an optional list of containers that are run in the same pod as the starrocks component. You can use this field to launch helper containers that run before the main container starts. See https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/pod-v1/#Container for how to configure a container. |
| `command` | []string | (Optional) Entrypoint array. Not executed within a shell. If this is not provided, it will use default entrypoint for different components: 1. For FE, it will use /opt/starrocks/fe_entrypoint.sh as the entrypoint. 2. For BE, it will use /opt/starrocks/be_entrypoint.sh as the entrypoint. 3. For CN, it will use /opt/starrocks/cn_entrypoint.sh as the entrypoint. More info: https://kubernetes.io/docs/tasks/inject-data-application/define-command-argument-container/#running-a-command-in-a-shell |
| `args` | []string | (Optional) Arguments to the entrypoint. If this is not provided, it will use $(FE_SERVICE_NAME) for all components. Variable references $(VAR_NAME) are expanded using the container’s environment. If a variable cannot be resolved, the reference in the input string will be unchanged. Double $$ are reduced to a single $, which allows for escaping the $(VAR_NAME) syntax: i.e. “$$(VAR_NAME)” will produce the string literal “$(VAR_NAME)”. Escaped references will never be expanded, regardless of whether the variable exists or not. Cannot be updated. More info: https://kubernetes.io/docs/tasks/inject-data-application/define-command-argument-container/#running-a-command-in-a-shell |
| `updateStrategy` | Kubernetes apps/v1.StatefulSetUpdateStrategy | (Optional) StarRocksCluster use StatefulSet to deploy FE/BE/CN components. UpdateStrategy indicates the StatefulSetUpdateStrategy that will be employed to update Pods in the StatefulSet when a revision is made to Template. See https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/#rolling-updates for more details. Note: The maxUnavailable field is in Alpha stage and it is honored only by API servers that are running with the MaxUnavailableStatefulSet feature gate enabled. |
| `readOnlyRootFilesystem` | bool | (Optional) Whether this container has a read-only root filesystem. Default is false. Note that: 1. This field cannot be set when spec.os.name is windows. 2. The FE/BE/CN container should support read-only root filesystem. The newest version of FE/BE/CN is 3.3.6, and does not support read-only root filesystem |
| `sysctls` | []Kubernetes core/v1.Sysctl | Sysctls defines a list of namespaced sysctls for the podSecurityContext.sysctls See https://kubernetes.io/docs/tasks/administer-cluster/sysctl-cluster/ for more details. |
| `persistentVolumeClaimRetentionPolicy` | Kubernetes apps/v1.StatefulSetPersistentVolumeClaimRetentionPolicy | PersistentVolumeClaimRetentionPolicy specifies the retention policy for PersistentVolumeClaims associated with the component. The WhenDeleted field is supported for all components, and it determines whether to delete PVCs when the StatefulSet is deleted. The WhenScaled field is only supported for the CN component. |
| `minReadySeconds` | int32 | (Optional) MinReadySeconds specifies the minimum number of seconds for which a newly created pod should be ready without any of its container crashing, for it to be considered available. Defaults to 0 (pod will be considered available as soon as it is ready). |
| `podManagementPolicy` | Kubernetes apps/v1.PodManagementPolicyType | (Optional) podManagementPolicy controls how pods are created during initial scale up, when replacing pods on nodes, or when scaling down. The default policy is Parallel which is not the same as statefulset’s default policy which maybe a not a good choice to use a different default value. |

## StarRocksComponentStatus

Appears on: StarRocksBeStatus, StarRocksCnStatus, StarRocksFeProxyStatus, StarRocksFeStatus

StarRocksComponentStatus represents the status of a starrocks component.

| Field | Type | Description |
|---|---|---|
| `serviceName` | string | the name of fe service exposed for user. |
| `failedInstances` | []string | FailedInstances failed pod names. |
| `creatingInstances` | []string | CreatingInstances in creating pod names. |
| `runningInstances` | []string | RunningInstances in running status pod names. |
| `resourceNames` | []string | ResourceNames the statefulset names of fe. |
| `phase` | ComponentPhase | Phase the value from all pods of component status. If component have one failed pod phase=failed, also if fe have one creating pod phase=creating, also if component all running phase=running, others unknown. |
| `reason` | string | Reason represents the reason of not running. |

## StarRocksFeProxySpec

Appears on: StarRocksClusterSpec

StarRocksFeProxySpec defines the specification for FE Proxy Note: it includes StarRocksLoadSpec, not StarRocksComponentSpec

| Field | Type | Description |
|---|---|---|
| `StarRocksLoadSpec` | StarRocksLoadSpec | (Members of `StarRocksLoadSpec` are embedded into this type.) |
| `resolver` | string |  |

## StarRocksFeProxyStatus

Appears on: StarRocksClusterStatus

| Field | Type | Description |
|---|---|---|
| `StarRocksComponentStatus` | StarRocksComponentStatus | (Members of `StarRocksComponentStatus` are embedded into this type.) |

## StarRocksFeSpec

Appears on: StarRocksClusterSpec

StarRocksFeSpec defines the desired state of fe.

| Field | Type | Description |
|---|---|---|
| `StarRocksComponentSpec` | StarRocksComponentSpec | (Members of `StarRocksComponentSpec` are embedded into this type.) |
| `feEnvVars` | []Kubernetes core/v1.EnvVar | (Optional) feEnvVars is a slice of environment variables that are added to the pods, the default is empty. |

## StarRocksFeStatus

Appears on: StarRocksClusterStatus

StarRocksFeStatus represents the status of starrocks fe.

| Field | Type | Description |
|---|---|---|
| `StarRocksComponentStatus` | StarRocksComponentStatus | (Members of `StarRocksComponentStatus` are embedded into this type.) |

## StarRocksLoadSpec

Appears on: StarRocksComponentSpec, StarRocksFeProxySpec

| Field | Type | Description |
|---|---|---|
| `ResourceRequirements` | Kubernetes core/v1.ResourceRequirements | (Members of `ResourceRequirements` are embedded into this type.) (Optional) defines the specification of resource cpu and mem. |
| `annotations` | map[string]string | annotation for pods. user can config monitor annotation for collect to monitor system. |
| `podLabels` | map[string]string | (Optional) the pod labels for user select or classify pods. |
| `replicas` | int32 | (Optional) Replicas is the number of desired Pods. When HPA policy is enabled with a fixed replica count in StarRocksCnSpec: every time the starrockscluster CR is applied, the replica count of the StatefulSet object in K8S will be reset to the value specified by the ‘Replicas’ field, erasing the value previously set by HPA. |
| `image` | string | (Optional) Image for a starrocks deployment. |
| `imagePullPolicy` | Kubernetes core/v1.PullPolicy | (Optional) Image pull policy. One of Always, Never, IfNotPresent. Defaults to IfNotPresent for compatibility. More info: https://kubernetes.io/docs/concepts/containers/images#updating-images |
| `imagePullSecrets` | []Kubernetes core/v1.LocalObjectReference | (Optional) ImagePullSecrets is an optional list of references to secrets in the same namespace to use for pulling any of the images used by this PodSpec. If specified, these secrets will be passed to individual puller implementations for them to use. More info: https://kubernetes.io/docs/concepts/containers/images#specifying-imagepullsecrets-on-a-pod |
| `schedulerName` | string | (Optional) SchedulerName is the name of the kubernetes scheduler that will be used to schedule the pods. |
| `nodeSelector` | map[string]string | (Optional) (Optional) If specified, the pod’s nodeSelector，displayName=“Map of nodeSelectors to match when scheduling pods on nodes” |
| `affinity` | Kubernetes core/v1.Affinity | (Optional) If specified, the pod’s scheduling constraints. |
| `tolerations` | []Kubernetes core/v1.Toleration | (Optional) (Optional) Tolerations for scheduling pods onto some dedicated nodes |
| `topologySpreadConstraints` | []Kubernetes core/v1.TopologySpreadConstraint | (Optional) (Optional) TopologySpreadConstraints for spreading pods across failure-domains More info: https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/ |
| `service` | StarRocksService | (Optional) Service defines the template for the associated Kubernetes Service object. |
| `storageVolumes` | []StorageVolume | (Optional) StorageVolumes defines the additional storage for FE meta or BE/CN storage. For FE component If the storage volume name is fe-meta or the volume mount path is /opt/starrocks/fe/meta, then it will be recognized as storing the FE meta. If the storage volume name is fe-log or the volume mount path is /opt/starrocks/fe/log, then it will be recognized as storing the FE log. For BE component If the storage volume name is be-storage(or be-data) or the volume mount path is /opt/starrocks/be/storage, then it will be recognized as storing the BE data. If the storage volume name is be-log or the volume mount path is /opt/starrocks/be/log, then it will be recognized as storing the BE log. For CN component If the storage volume name is cn-log or the volume mount path is /opt/starrocks/cn/log, then it will be recognized as storing the cn log. If operator can’t find the above storage volume names or the volume mount paths, it will create default storage volumes by using emptyDir. |
| `serviceAccount` | string | serviceAccount for access cloud service. |
| `configMapInfo` | ConfigMapInfo | (Optional) the reference for configMap which store the config info to start starrocks. e.g. be.conf, fe.conf, cn.conf. |
| `startupProbeFailureSeconds` | int32 | (Optional) StartupProbeFailureSeconds defines the total failure seconds of startup Probe. Default failureThreshold is 60 and the periodSeconds is 5, this means the startup will fail if the pod can’t start in 300 seconds. Your StartupProbeFailureSeconds is the total time of seconds before startupProbe give up and fail the container start. If startupProbeFailureSeconds can’t be divided by defaultPeriodSeconds, the failureThreshold will be rounded up. Note: you can set it to 0 to disable the startup probe. |
| `livenessProbeFailureSeconds` | int32 | (Optional) LivenessProbeFailureSeconds defines the total failure seconds of liveness Probe. Default failureThreshold is 3 and the periodSeconds is 5, this means the liveness will fail if the pod can’t respond in 15 seconds. Your LivenessProbeFailureSeconds is the total time of seconds before the container restart. If LivenessProbeFailureSeconds can’t be divided by defaultPeriodSeconds, the failureThreshold will be rounded up. Note: you can set it to 0 to disable the liveness probe. |
| `readinessProbeFailureSeconds` | int32 | (Optional) ReadinessProbeFailureSeconds defines the total failure seconds of readiness Probe. Default failureThreshold is 3 and the periodSeconds is 5, this means the readiness will fail if the pod can’t respond in 15 seconds. Your ReadinessProbeFailureSeconds is the total time of seconds before pods becomes not ready. If ReadinessProbeFailureSeconds can’t be divided by defaultPeriodSeconds, the failureThreshold will be rounded up. Note: you can set it to 0 to disable the readiness probe. |
| `lifecycle` | Kubernetes core/v1.Lifecycle | (Optional) Lifecycle describes actions that the management system should take in response to container lifecycle events. By default, Operator will add corresponding preStop hooks for different components. For example, the preStop script for the FE Component is /opt/starrocks/fe_prestop.sh, for the BE Component is /opt/starrocks/be_prestop.sh, and for the CN Component is /opt/starrocks/cn_prestop.sh. |
| `shareProcessNamespace` | bool | (Optional) Share a single process namespace between all of the containers in a pod. When this is set containers will be able to view and signal processes from other containers in the same pod, and the first process in each container will not be assigned PID 1. Optional: Default to false. |

## StarRocksProbe

StarRocksProbe defines the mode for probe be alive.

| Field | Type | Description |
|---|---|---|
| `type` | string | Type identifies the mode of probe main container |
| `initialDelaySeconds` | int32 | (Optional) Number of seconds after the container has started before liveness probes are initiated. Default to 10 seconds. |
| `periodSeconds` | int32 | (Optional) How often (in seconds) to perform the probe. Default to Kubernetes default (10 seconds). Minimum value is 1. |

## StarRocksService

Appears on: StarRocksLoadSpec

StarRocksService defines external service for starrocks component.

| Field | Type | Description |
|---|---|---|
| `annotations` | map[string]string | (Optional) Annotations’ store Kubernetes Service annotations. These will be added to the external service only (not internal). |
| `labels` | map[string]string | (Optional) Labels store Kubernetes Service labels. These will be added to the external service only (not internal). StarRocks may add its own default labels. |
| `type` | Kubernetes core/v1.ServiceType | (Optional) type of service,the possible value for the service type are : ClusterIP, NodePort, LoadBalancer,ExternalName. More info: https://kubernetes.io/docs/concepts/services-networking/service/#publishing-services-service-types |
| `loadBalancerIP` | string | (Optional) Only applies to Service Type: LoadBalancer. This feature depends on whether the underlying cloud-provider supports specifying the loadBalancerIP when a load balancer is created. This field will be ignored if the cloud-provider does not support the feature. This field was under-specified and its meaning varies across implementations, and it cannot support dual-stack. As of Kubernetes v1.24, users are encouraged to use implementation-specific annotations when available. This field may be removed in a future API version. |
| `ports` | []StarRocksServicePort | (Optional) Ports are the ports that are exposed by this service. You can override the default port information by specifying the same StarRocksServicePort.Name in the ports list. e.g. if you want to use a dedicated node port, you can just specify the StarRocksServicePort.Name and StarRocksServicePort.NodePort field. |
| `loadBalancerSourceRanges` | []string | (Optional) If specified and supported by the platform, this will restrict traffic through the cloud-provider load-balancer will be restricted to the specified client IPs. This field will be ignored if the cloud-provider does not support the feature. More info: https://kubernetes.io/docs/tasks/access-application-cluster/create-external-load-balancer/ |
| `externalTrafficPolicy` | Kubernetes core/v1.ServiceExternalTrafficPolicyType | (Optional) ExternalTrafficPolicy describes how nodes distribute service traffic they receive on one of the Service’s “externally-facing” addresses (NodePorts, ExternalIPs, and LoadBalancer IPs). “Local” preserves the client source IP and avoids a second hop, but risks unbalanced traffic spreading. “Cluster” obscures the client source IP and may cause a second hop to another node, but should have good overall load-spreading. Kubernetes only allows this field when type is NodePort or LoadBalancer; if it is set for a service of another type, reconciliation fails and the error is reported in the cluster status. More info: https://kubernetes.io/docs/tasks/access-application-cluster/create-external-load-balancer/#preserving-the-client-source-ip |

## StarRocksServicePort

Appears on: StarRocksService

StarRocksServicePort defines the port that will be exposed by this service. To assign a specific port or nodePort to a service, you should specify them by the corresponding name or containerPort in the service configuration. If both containerPort and name are specified, containerPort takes precedence.

| Field | Type | Description |
|---|---|---|
| `name` | string | (Optional) Name of this port within the service. For fe, port name can be http, query, rpc, edit-log, and their default container port is 8030, 9030, 9020, 9010. For be, port name can be webserver, heartbeat, brpc, be, and their default container port is 8040, 9050, 8060, 9060. For cn, port name can be webserver, heartbeat, brpc, thrift, and their default container port is 8040, 9050, 8060, 9060. For fe proxy, port name can be http-port, and its default container port is 8080. |
| `port` | int32 | (Optional) Port that will be exposed by this service. |
| `containerPort` | int32 | (Optional) ContainerPort of the service port. For fe, port name can be http, query, rpc, edit-log, and their default container port is 8030, 9030, 9020, 9010. For be, port name can be webserver, heartbeat, brpc, be, and their default container port is 8040, 9050, 8060, 9060. For cn, port name can be webserver, heartbeat, brpc, thrift, and their default container port is 8040, 9050, 8060, 9060. For fe proxy, port name can be http-port, and its default container port is 8080. |
| `nodePort` | int32 | (Optional) NodePort is used to specify the port on each node on which the service is exposed. The range of valid ports is 30000-32767 |

## StarRocksWarehouse

StarRocksWarehouse defines a starrocks warehouse.

| Field | Type | Description |
|---|---|---|
| `metadata` | Kubernetes meta/v1.ObjectMeta | Refer to the Kubernetes API documentation for the fields of the `metadata` field. |
| `spec` | StarRocksWarehouseSpec | Spec represents the specification of desired state of a starrocks warehouse. `starRocksCluster` string |
| `template` | WarehouseComponentSpec | Template define component configuration. |

## StarRocksWarehouseSpec

Appears on: StarRocksWarehouse

StarRocksWarehouseSpec defines the desired state of StarRocksWarehouse

| Field | Type | Description |
|---|---|---|
| `starRocksCluster` | string | StarRocksCluster is the name of a StarRocksCluster which the warehouse belongs to. |
| `template` | WarehouseComponentSpec | Template define component configuration. |

## StarRocksWarehouseStatus

Appears on: StarRocksWarehouse

StarRocksWarehouseStatus defines the observed state of StarRocksWarehouse.

| Field | Type | Description |
|---|---|---|
| `WarehouseComponentStatus` | StarRocksCnStatus | (Members of `WarehouseComponentStatus` are embedded into this type.) |

## StorageVolume

Appears on: StarRocksLoadSpec

StorageVolume defines additional PVC template for StatefulSets and volumeMount for pods that mount this PVC.

| Field | Type | Description |
|---|---|---|
| `name` | string | name of a storage volume. |
| `storageClassName` | string | (Optional) storageClassName is the name of the StorageClass required by the claim. If storageClassName is not set, the default StorageClass of kubernetes will be used. there are some special storageClassName: emptyDir, hostPath, csi. In this case, It will use emptyDir, hostPath or an ephemeral inline CSI volume, not PVC. More info: https://kubernetes.io/docs/concepts/storage/persistent-volumes#class-1 |
| `storageSize` | string | (Optional) StorageSize is a valid memory size type based on powers-of-2, so 1Mi is 1024Ki. Supported units:Mi, Gi, GiB, Ti, Ti, Pi, Ei, Ex: `512Mi`. It will take effect only when storageClassName is real storage class, not emptyDir or hostPath. |
| `hostPath` | Kubernetes core/v1.HostPathVolumeSource | (Optional) HostPath Represents a host path mapped into a pod. If StorageClassName is hostPath, HostPath is required. |
| `csi` | Kubernetes core/v1.CSIVolumeSource | (Optional) CSI represents an ephemeral inline CSI volume mounted into the pod, for example the SPIFFE workload API socket provided by driver csi.spiffe.io. Unlike a PVC-backed volume, its lifecycle is tied to the pod and no PersistentVolumeClaim is created for it. If StorageClassName is csi, CSI is required. |
| `mountPath` | string | MountPath specify the path of volume mount. |
| `subPath` | string | SubPath within the volume from which the container’s volume should be mounted. Defaults to “” (volume’s root). |
| `readOnly` | bool | (Optional) ReadOnly mounts the volume read-only inside the container if true, read-write otherwise. This sets readOnly on the container’s volumeMount, which is what the container’s mount table reports. It is independent of any read-only flag on the volume source itself: for a CSI volume, csi.readOnly asks the driver to publish the volume read-only, while this field controls how the volume is mounted into the container. Setting both is the usual intent. Defaults to false. |

## WarehouseComponentSpec

Appears on: StarRocksWarehouseSpec

WarehouseComponentSpec defines the desired state of component.

| Field | Type | Description |
|---|---|---|
| `StarRocksComponentSpec` | StarRocksComponentSpec | (Members of `StarRocksComponentSpec` are embedded into this type.) |
| `envVars` | []Kubernetes core/v1.EnvVar | (Optional) envVars is a slice of environment variables that are added to the pods, the default is empty. |
| `autoScalingPolicy` | AutoScalingPolicy | AutoScalingPolicy defines auto scaling policy |
