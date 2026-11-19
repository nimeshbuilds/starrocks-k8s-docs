# 13. Upgrades and day-2 operations

Upgrading StarRocks, upgrading the operator, and the routine operations around a running cluster.

## Before any StarRocks upgrade

From the upstream upgrade guide:

1. Read the release notes for the target version and every version in between. Note behaviour changes and changes to integrations. Release notes are in [`release_notes/`](../upstream/starrocks/docs/en/release_notes/).
2. Check the deployment prerequisites of the target version, for example the JDK it needs. On Kubernetes the image carries the JDK, so this mainly matters for custom images.
3. Upgrade one minor version at a time. Skipping is technically possible but upstream strongly recommends consecutive steps.
4. For a minor or major version change, apply the compatibility configuration first. The universal step is to disable tablet clone before the upgrade and re-enable it after. Version-specific steps are in the upstream page.
5. Test on one node or a non-production cluster first.
6. Have a downgrade plan. See [`downgrade.md`](../upstream/starrocks/docs/en/deployment/manage_deployment/downgrade.md).

You cannot convert between shared-nothing and shared-data by upgrading.

## Upgrade order

StarRocks supports rolling upgrades. BEs and CNs are backward compatible with FEs, so the rule is:

> **Upgrade BE and CN first, then FE.** Within FE, followers first and the leader last.

For a downgrade the order is reversed: FE first, then BE and CN.

### With a manifest

Change one component's image at a time and wait for it to finish.

```bash
# 1. BE (shared-nothing) and CN
kubectl -n starrocks patch starrockscluster sr --type=merge \
  -p '{"spec":{"starRocksBeSpec":{"image":"starrocks/be-ubuntu:<new>"}}}'
kubectl -n starrocks patch starrockscluster sr --type=merge \
  -p '{"spec":{"starRocksCnSpec":{"image":"starrocks/cn-ubuntu:<new>"}}}'
kubectl -n starrocks rollout status statefulset/sr-cn

# 2. FE, after BE and CN are done
kubectl -n starrocks patch starrockscluster sr --type=merge \
  -p '{"spec":{"starRocksFeSpec":{"image":"starrocks/fe-ubuntu:<new>"}}}'
kubectl -n starrocks rollout status statefulset/sr-fe
```

Verify between steps:

```sql
SHOW BACKENDS;        -- Version column, Alive = true
SHOW COMPUTE NODES;
SHOW FRONTENDS;       -- Version column, one LEADER, all Alive
```

### With Helm

A single `helm upgrade` that changes every image tag hands all the changes to the operator at once. The operator documentation does not describe the order it then applies them in. To keep to the documented order, run two upgrades: first with only the BE and CN tags changed, then with the FE tag.

```yaml
# step 1
starrocksCnSpec: {image: {tag: "<new>"}}
starrocksBeSpec: {image: {tag: "<new>"}}
starrocksFESpec: {image: {tag: "<old>"}}
```

If you use `starrocksCluster.componentValues.image.tag` to set one tag for all components, set per-component tags during the upgrade instead. Component values override `componentValues`.

### Controlling the rollout

| Setting | Effect |
|---|---|
| `spec.waitForFullRollout: true` | The operator waits until every FE replica is ready on the new revision before it touches BE and CN. Stops a failing FE rollout from cascading. |
| `updateStrategy` | StatefulSet update strategy per component. `rollingUpdate.partition` gives a canary: only pods with an ordinal at or above the partition are updated. |
| `maxUnavailablePods` (Helm) / `updateStrategy.rollingUpdate.maxUnavailable` | Update more than one pod at a time. Needs the `MaxUnavailableStatefulSet` feature gate. Cannot be 0. |
| `minReadySeconds` | Hold each new pod as "not yet available" for a soak period |
| `terminationGracePeriodSeconds` and `min_graceful_exit_time_second` | Let in-flight queries finish. See [Configuration](05-configuration.md#graceful-shutdown). |
| `startupProbeFailureSeconds` | Raise it if an FE needs longer than 300 seconds to replay metadata at startup |

Pin exact image tags. With a moving tag such as `4.1-latest`, a pod restart can pull a different build than its neighbours.

## Upgrade the operator and CRDs

The operator and StarRocks are versioned separately. Upgrading the operator does not restart StarRocks pods by itself.

1. Read the operator release notes: https://github.com/StarRocks/starrocks-kubernetes-operator/releases. The `CHANGELOG.md` in the repository stops at 1.9.8, while the charts are at 1.11.8, so the release page is the place to look.
2. Update the CRDs first. Helm does not upgrade existing CRDs.

   ```bash
   kubectl replace -f starrocks.com_starrocksclusters.yaml
   kubectl replace -f starrocks.com_starrockswarehouses.yaml   # if you use warehouses
   ```

   Use `replace` or server-side apply. Client-side `kubectl apply` can fail on the annotation size limit.

3. Update the operator.

   ```bash
   helm upgrade starrocks-operator starrocks/operator -n starrocks -f operator-values.yaml
   # or
   kubectl apply -f operator.yaml
   ```

4. Check the operator log and that `kubectl get starrockscluster` still shows `running`.

A new operator version can change the pod template it generates, which may roll the StarRocks pods on its first reconcile. Do operator upgrades in a maintenance window the first time.

Features with a minimum operator version:

| Feature | Operator version |
|---|---|
| Prometheus annotations and ServiceMonitor | 1.7.1 |
| Split charts `operator` and `starrocks` | 1.8.0 |
| `StarRocksWarehouse` | 1.9.0 |
| Read-only root filesystem support | 1.9.9 |
| Shared-data disaster recovery | 1.10.0 |
| Reworked CN HPA | 1.11.0 |

## Changing configuration

| Change | How | Restart |
|---|---|---|
| Static parameter | Edit the ConfigMap or Helm `config`, roll the component | Yes |
| Dynamic FE parameter | `ADMIN SET FRONTEND CONFIG`, and also write it to `fe.conf` | No |
| Dynamic BE or CN parameter | `UPDATE information_schema.be_configs`, and also write it to the config file | No |
| Session or global variable | `SET GLOBAL` | No |

## Restarting a component

There is no restart field. Change something in the pod template, for example an annotation:

```bash
kubectl -n starrocks patch starrockscluster sr --type=merge \
  -p '{"spec":{"starRocksCnSpec":{"annotations":{"restarted-at":"2026-01-01T00:00:00Z"}}}}'
```

Deleting a single pod also works for a one-off. The StatefulSet recreates it.

## Routine checks

```bash
kubectl -n starrocks get starrockscluster
kubectl -n starrocks get pods -o wide
kubectl -n starrocks get pvc
kubectl -n starrocks top pods
kubectl -n starrocks get events --sort-by=.lastTimestamp | tail -20
```

```sql
SHOW FRONTENDS;
SHOW BACKENDS;
SHOW COMPUTE NODES;
SHOW PROC '/statistic';          -- tablet health, shared-nothing
SHOW RESOURCE GROUPS ALL;
```

Watch for: an FE that is not `Alive`, no `LEADER`, FE metadata disk filling, BEs with unhealthy tablets, CNs registered but not alive after a scale-in.

## Node maintenance

- **CN.** Draining is safe. Queries running on the pod at that moment may fail or retry, and its cache is lost if the cache is node-local.
- **BE.** Drain one node at a time and wait for the BE to return and report healthy tablets before the next.
- **FE.** Drain one at a time. Never take down a majority of FEs together. With three FEs, that means one at a time.
- Add PodDisruptionBudgets for FE and BE. The operator does not create them.

## Backup and recovery

| What | How |
|---|---|
| Shared-data cluster metadata | Automated cluster snapshots to object storage, restored by the operator's disaster recovery mode. See [Disaster recovery](14-disaster-recovery.md). |
| Shared-nothing table data | `BACKUP` and `RESTORE` to a repository. See [`Backup_and_restore.md`](../upstream/starrocks/docs/en/administration/management/Backup_and_restore.md). |
| FE metadata corruption | [`Meta_recovery.md`](../upstream/starrocks/docs/en/administration/Meta_recovery.md) |
| Data recovery | [`Data_recovery.md`](../upstream/starrocks/docs/en/administration/Data_recovery.md) |
| Cluster definition | Keep the `StarRocksCluster` manifest or Helm values in version control |

External catalogs hold no data. Recreating the catalog recreates access.

## Deleting things safely

| Action | Result |
|---|---|
| Delete a CN pod | Recreated. Safe. |
| Delete a BE pod | Recreated with the same PVC. Safe one at a time. |
| Delete an FE pod | Recreated with the same PVC. Safe one at a time. |
| Delete a PVC of FE metadata or BE data | Data loss for that node. On a single-FE cluster, loss of the cluster. |
| Delete the `StarRocksCluster` | Pods and services removed. PVCs kept unless the retention policy says otherwise. |
| Delete the CRD | Every cluster object of that kind is deleted. |

## Upstream sources

- [`upgrade.md`](../upstream/starrocks/docs/en/deployment/manage_deployment/upgrade.md)
- [`downgrade.md`](../upstream/starrocks/docs/en/deployment/manage_deployment/downgrade.md)
- [`deploy_starrocks_with_operator_howto.md`](../upstream/starrocks-kubernetes-operator/doc/deploy_starrocks_with_operator_howto.md), sections 3.2 and 3.3
- [`CHANGELOG.md`](../upstream/starrocks-kubernetes-operator/CHANGELOG.md)
- [`Scale_up_down.md`](../upstream/starrocks/docs/en/administration/management/Scale_up_down.md)
- [`graceful_exit.md`](../upstream/starrocks/docs/en/administration/management/graceful_exit.md)
