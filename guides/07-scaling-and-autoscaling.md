# 7. Scaling and autoscaling

Scaling rules differ sharply by component. CN is safe to scale freely. FE and BE are not.

| Component | Scale out | Scale in |
|---|---|---|
| FE | Raise `replicas` | Manual procedure, one step at a time. Never below 3 once you have 3. |
| BE | Raise `replicas`. Data rebalances in the background. | Manual decommission first, then lower `replicas`. |
| CN | Raise `replicas`, or autoscale | Lower `replicas`, or autoscale |

## Manual scaling

```bash
# CN to 6
kubectl -n starrocks patch starrockscluster sr --type=merge \
  -p '{"spec":{"starRocksCnSpec":{"replicas":6}}}'

# BE to 9
kubectl -n starrocks patch starrockscluster sr --type=merge \
  -p '{"spec":{"starRocksBeSpec":{"replicas":9}}}'

# FE to 5
kubectl -n starrocks patch starrockscluster sr --type=merge \
  -p '{"spec":{"starRocksFeSpec":{"replicas":5}}}'
```

With Helm, change `replicas` in the values file and run `helm upgrade`.

## Scaling in FE

FE holds metadata in a replicated group, so removing nodes has rules:

1. Remove nodes one step at a time. Wait for each step to finish.
2. Each step must remove fewer than half of the nodes. Go 7 to 5 to 3, never 7 to 3.
3. You cannot go from 3 to 1. The metadata group cannot switch from HA to single-node mode.

Procedure for each node:

```sql
-- 1. Find the highest-ordinal FE
SHOW FRONTENDS;

-- 2. Drop it from the cluster
ALTER SYSTEM DROP FOLLOWER "sr-fe-4.sr-fe-search.starrocks.svc.cluster.local:9010";
```

```bash
# 3. Lower replicas by one
kubectl -n starrocks patch starrockscluster sr --type=merge \
  -p '{"spec":{"starRocksFeSpec":{"replicas":4}}}'
```

Then run `SHOW FRONTENDS` on a remaining FE and confirm every FE agrees on the member list before repeating.

## Scaling in BE (shared-nothing)

Lowering `replicas` only deletes pods. The operator does not move data off them first. If the removed BEs held the only healthy replicas of some tablets, queries fail.

Recovery from a mistake: the PVCs are still there, so set `replicas` back to the old number and the BEs return with their data.

The correct procedure, repeated for each BE starting from the highest ordinal:

```sql
-- 1. Identify the BE
SHOW BACKENDS;

-- 2. Decommission it. Data migrates to the remaining BEs.
ALTER SYSTEM DECOMMISSION BACKEND "sr-be-5.sr-be-search.starrocks.svc.cluster.local:9050";

-- 3. Wait until SystemDecommissioned is true and TabletNum is 0
SHOW BACKENDS;

-- 4. Drop it
ALTER SYSTEM DROP BACKEND "sr-be-5.sr-be-search.starrocks.svc.cluster.local:9050";
```

```bash
# 5. Lower replicas by one
kubectl -n starrocks patch starrockscluster sr --type=merge \
  -p '{"spec":{"starRocksBeSpec":{"replicas":5}}}'
```

Keep at least as many BEs as your replication factor, which is 3 by default.

## Autoscaling CN with HPA

The operator creates a HorizontalPodAutoscaler from `autoScalingPolicy`. Needs metrics-server. Operator 1.11.0 reworked this area: cleanup when the policy is removed, several HPA API versions, graceful node deregistration, and no fighting between operator and HPA over replicas. Use 1.11.0 or later.

```yaml
starRocksCnSpec:
  image: starrocks/cn-ubuntu:<version>
  # no replicas field
  requests: {cpu: 16, memory: 64Gi}
  limits:   {cpu: 16, memory: 64Gi}
  autoScalingPolicy:
    version: v2
    minReplicas: 2
    maxReplicas: 10
    hpaPolicy:
      metrics:
        - type: Resource
          resource:
            name: cpu
            target: {type: Utilization, averageUtilization: 60}
        - type: Resource
          resource:
            name: memory
            target: {type: Utilization, averageUtilization: 70}
      behavior:
        scaleUp:
          policies:
            - {type: Pods, value: 2, periodSeconds: 60}
        scaleDown:
          policies:
            - {type: Pods, value: 1, periodSeconds: 120}
  persistentVolumeClaimRetentionPolicy:
    whenScaled: Delete
```

Rules:

- **Remove `replicas` from `starRocksCnSpec`.** If both are set, each apply resets the count and erases the autoscaler's decision.
- `version` selects the HPA API: `v1`, `v2beta2` or `v2`. The chart comment says `v2beta2` is the default. Use `v2` on current Kubernetes.
- `hpaPolicy.metrics` and `hpaPolicy.behavior` are standard HPA fields.
- Utilization is measured against `requests`, so set them realistically. Requests equal to limits makes the numbers predictable.
- `scaleDown.selectPolicy: Disabled` turns off automatic scale-in. Several upstream examples ship that way.
- Add `whenScaled: Delete` if CN pods have PVCs, so scaled-in pods do not leave volumes behind.

The HPA is named `<cluster>-cn-autoscaler` and targets the `StarRocksCluster` object:

```bash
kubectl -n starrocks get hpa
kubectl -n starrocks describe hpa sr-cn-autoscaler
```

Helm uses the same block under `starrocksCnSpec.autoScalingPolicy`, with `starrocksCluster.enabledCn: true`.

### What happens on scale-in

Pods are removed gracefully and their PVCs are deleted if `whenScaled: Delete` is set. A removed CN can still be listed, not alive, in `SHOW COMPUTE NODES`. Drop stale entries with `ALTER SYSTEM DROP COMPUTE NODE` if they linger.

### Memory as a scaling signal

CPU utilization tracks query load well. Memory is a weaker signal for CN, because caches hold memory after load drops and scale-in may never trigger. Start with CPU and add memory only as a scale-out safety net.

## Autoscaling CN with KEDA

AWS Data on EKS scales CN on query activity instead of resource usage, with scale to zero. It points a KEDA `ScaledObject` at the CN StatefulSet and uses Prometheus triggers.

| Setting | Value in the example |
|---|---|
| Target | StatefulSet `<cluster>-cn` |
| `minReplicaCount` / `maxReplicaCount` | 0 / 10 |
| `pollingInterval` / `cooldownPeriod` | 30 s / 300 s |
| Trigger 1 | `sum(rate(starrocks_fe_query_total{job="<cluster>"}[2m]))`, threshold 5, activation 0.1 |
| Trigger 2 | `sum(starrocks_fe_connection_total{job="<cluster>"})`, threshold 20, activation 1 |
| Scale-up | 2 pods per 30 s, no stabilization window |
| Scale-down | 1 pod per 60 s, 300 s stabilization window |

Points to carry over:

- The CN spec must not set `replicas`, and must not also set `autoScalingPolicy`. One autoscaler only.
- Scale to zero means the first query waits for a pod and possibly a node, then runs against a cold cache. Use `minReplicaCount: 1` for latency-sensitive workloads.
- The triggers read FE metrics, so Prometheus must be scraping FE. See [Observability](12-observability.md).
- The `job` label in the queries comes from the Data on EKS PodMonitor relabeling. Adjust the queries to your own labels.

The manifest is at [`cn-keda-scaledobject.yaml`](../upstream/data-on-eks/infra/terraform/manifests/starrocks/cn-keda-scaledobject.yaml). It contains Terraform template variables (`${...}`) that you must replace.

## Node autoscaling

Pod autoscaling only helps if nodes can appear. With Cluster Autoscaler or Karpenter:

- Give CN pods a `nodeSelector` or affinity for the node pool you want them on.
- A StarRocks shared-data cluster expects every CN to have the same hardware specification. Restrict the node pool to one instance type or size so autoscaling does not mix them.
- Expect a few minutes for a new node. Keep `minReplicas` high enough to absorb that.
- Protect FE and BE pods from voluntary node consolidation. They are stateful.

## Warehouses

A warehouse is a named group of CNs with its own lifecycle and its own autoscaler, attached to an existing cluster. Upstream marks it as an enterprise feature needing StarRocks enterprise 3.2.0 or later, operator 1.9.0 or later, and an enterprise CN image.

```bash
# CRD, then restart the operator so it sees the new kind
kubectl apply -f starrocks.com_starrockswarehouses.yaml
kubectl -n starrocks rollout restart deployment kube-starrocks-operator

kubectl -n starrocks apply -f wh1.yaml
# or
helm -n starrocks install wh1 starrocks/warehouse -f wh1-values.yaml
```

```sql
SHOW WAREHOUSES;
```

Things to know:

- The warehouse CR must be in the same namespace as its cluster.
- A dash in the CR name becomes an underscore in the SQL warehouse name.
- BE and CN nodes of the main cluster belong to `default_warehouse`.
- Change a warehouse by editing its manifest or values file and re-applying. Upstream advises against `kubectl edit`.
- Deleting the CR makes the operator run `DROP WAREHOUSE`, which also drops the warehouse's properties and grants. This is best effort. Check with `SHOW WAREHOUSES` afterwards.
- To delete the CR but keep the warehouse definition in StarRocks, annotate it first with `starrocks.com/skip-fe-cleanup=true` and wait for the operator to copy the annotation to the CN StatefulSet. The full procedure, and how to reverse it, is in the upstream how-to.

On the open-source edition, the alternatives for workload isolation are resource groups inside one cluster, or separate clusters. See [Resource management](11-resource-management.md).

## Upstream sources

- [`scale_in_fe_nodes_howto.md`](../upstream/starrocks-kubernetes-operator/doc/scale_in_fe_nodes_howto.md)
- [`scale_in_shared_nothing_cluster_howto.md`](../upstream/starrocks-kubernetes-operator/doc/scale_in_shared_nothing_cluster_howto.md)
- [`hpa_dynamic_scaling_with_helm_howto.md`](../upstream/starrocks-kubernetes-operator/doc/hpa_dynamic_scaling_with_helm_howto.md)
- [`automatic_scaling_for_cn_nodes_howto.md`](../upstream/starrocks-kubernetes-operator/doc/automatic_scaling_for_cn_nodes_howto.md) (for operator versions before 1.11.0)
- [`deploy_warehouse_howto.md`](../upstream/starrocks-kubernetes-operator/doc/deploy_warehouse_howto.md)
- [`deploy_a_starrocks_cluster_with_cn.yaml`](../upstream/starrocks-kubernetes-operator/examples/starrocks/deploy_a_starrocks_cluster_with_cn.yaml)
- [`Scale_up_down.md`](../upstream/starrocks/docs/en/administration/management/Scale_up_down.md)
- Data on EKS: [`infra.md`](../upstream/data-on-eks/website/docs/datastacks/databases/starrocks-on-eks/infra.md)
