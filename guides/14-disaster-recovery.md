# 14. Disaster recovery

Restoring a shared-data cluster from a cluster snapshot, using the operator's disaster recovery mode.

This applies to **shared-data** clusters. Table data already lives in object storage. What has to be recovered is the cluster metadata, and StarRocks can snapshot that into the same object storage. For shared-nothing clusters, use `BACKUP` and `RESTORE` instead. See [`Backup_and_restore.md`](../upstream/starrocks/docs/en/administration/management/Backup_and_restore.md).

Requires operator and CRD 1.10.0 or later.

## How it works

1. **Snapshots.** FE periodically writes a cluster snapshot (metadata image) to a storage volume. Data files are already there.
2. **Loss.** The Kubernetes cluster, the FE volumes, or the whole namespace is gone. The bucket survives.
3. **Restore.** You deploy a new, empty cluster with `disasterRecovery.enabled: true` and a `cluster_snapshot.yaml` that points at the snapshot. The operator starts one FE in restore mode, waits for it to finish, then brings the cluster up normally.

### What the operator does in restore mode

- Pauses reconciliation of BE and CN.
- Checks that the FE spec mounts a ConfigMap with `subPath: cluster_snapshot.yaml`.
- Rewrites the FE StatefulSet to:
  - run a single FE replica,
  - inject the environment variables `RESTORE_CLUSTER_GENERATION` and `RESTORE_CLUSTER_SNAPSHOT`,
  - remove the startup and liveness probes, because restore can take a long time,
  - change the readiness probe to check that port 9030 accepts connections, which signals that the restore is complete.
- When the FE is ready, restarts the cluster with its normal spec, including the other FEs and the CNs.

### Triggering and phases

```yaml
spec:
  disasterRecovery:
    enabled: true
    generation: 1
status:
  disasterRecoveryStatus:
    phase: todo | doing | done
    observedGeneration: 1
```

- A restore starts when `enabled` is `true` and either there is no status yet or `observedGeneration` is lower than `generation`.
- Phases: `todo` when detected, `doing` once the modified StatefulSet is applied, `done` when the FE pod is ready.
- To run a restore again, for example after fixing the snapshot path, raise `generation`.

## Step 1: turn on snapshots in the running cluster

```sql
ADMIN SET AUTOMATED CLUSTER SNAPSHOT ON STORAGE VOLUME builtin_storage_volume;
```

The statement accepts an `INTERVAL <value> <unit>` clause. Without it, the interval comes from the FE setting `automated_cluster_snapshot_interval_seconds`, which defaults to 600 seconds. The upstream operator walkthrough sets it to 60 seconds only to make the demo fast. Pick an interval that matches how much recent metadata change you can afford to lose.

Find the snapshots:

```sql
SELECT * FROM information_schema.cluster_snapshot_jobs;   -- progress and errors
SELECT * FROM information_schema.cluster_snapshots;       -- latest snapshot
```

Record the `STORAGE_PATH` of the snapshot, which looks like:

```
s3://<bucket>/<prefix>/<cluster-uuid>/meta/image/automated_cluster_snapshot_<timestamp>
```

Monitor that snapshots keep being produced. A restore is only as fresh as the last one. Store the path, or the rule for deriving it, somewhere outside the cluster.

## Step 2: prepare the restore configuration

Keep your normal values file. Add an override file for the restore.

```yaml
# override.yaml, for the kube-starrocks chart
starrocks:
  starrocksCluster:
    disasterRecovery:
      enabled: true
      generation: 1
  starrocksFESpec:
    configMaps:
      - name: cluster-snapshot
        mountPath: /opt/starrocks/fe/conf/cluster_snapshot.yaml
        subPath: cluster_snapshot.yaml
  configMaps:
    - name: cluster-snapshot
      data:
        cluster_snapshot.yaml: |
          cluster_snapshot:
            cluster_snapshot_path: s3://<bucket>/<prefix>/<cluster-uuid>/meta/image/automated_cluster_snapshot_<timestamp>
            storage_volume_name: builtin_storage_volume

          # leave blank. The operator adds the other FEs.
          frontends:

          # leave blank. The operator adds the CNs.
          compute_nodes:

          # needed when restoring a cloned snapshot
          storage_volumes:
            - name: builtin_storage_volume
              type: S3
              location: s3://<bucket>/<prefix>
              comment: restored volume
              properties:
                - key: aws.s3.region
                  value: <region>
                - key: aws.s3.endpoint
                  value: <endpoint>
                - key: aws.s3.use_aws_sdk_default_behavior
                  value: "true"
```

The upstream example uses static `aws.s3.access_key` and `aws.s3.secret_key` properties. With IAM roles, use the credential properties that match how your storage volume was created.

With a raw `StarRocksCluster`, set `spec.disasterRecovery` and add the ConfigMap under `spec.starRocksFeSpec.configMaps` with the same `mountPath` and `subPath`.

## Step 3: deploy the restore

Start from a clean slate. The target must not have old FE metadata or CN cache.

```bash
# make sure no PVCs from a previous cluster of the same name remain
kubectl -n starrocks get pvc

helm install sr starrocks/kube-starrocks -n starrocks \
  -f starrocks-values.yaml -f override.yaml
```

Watch it:

```bash
kubectl -n starrocks get starrockscluster sr -o jsonpath='{.status.disasterRecoveryStatus}'
kubectl -n starrocks get pods -w
kubectl -n starrocks logs sr-fe-0 -f
```

Expect one FE pod at first. When `phase` is `done`, the remaining FEs and the CNs appear.

## Step 4: verify, then return to normal

```sql
SHOW FRONTENDS;
SHOW COMPUTE NODES;
SHOW DATABASES;
SELECT count(*) FROM <a table you know>;
```

If you want to inspect the restored cluster before it scales out, upstream suggests setting FE replicas to 1 and disabling BE and CN in the restore values, then enabling them afterwards.

Once verified:

1. Remove the `disasterRecovery` block, or leave it with the same `generation`. It only acts when `generation` rises.
2. Remove the `cluster_snapshot.yaml` mount at a convenient time.
3. Turn automated snapshots on again in the new cluster.
4. Recreate anything that lived outside the metadata snapshot: Kubernetes Secrets, the root password Secret, network policies, monitoring.

## Planning notes

| Question | Answer |
|---|---|
| What is the recovery point? | The time of the last successful snapshot |
| What is not in the snapshot? | Kubernetes objects, and anything on local disks such as caches and logs |
| Can I restore into another region or account? | The snapshot and data must be reachable from the new cluster. The `storage_volumes` section exists for restoring a cloned snapshot at a different location. Test it. |
| Does it need the same cluster name? | Not for StarRocks, but Service names follow the cluster name, so clients may need repointing |
| Are external catalogs restored? | Catalog definitions are metadata, so they come back. Their IAM access depends on the new pods' ServiceAccount. |

Run a restore drill before you need one. The upstream walkthrough is a complete, copyable drill: create a cluster, load data, snapshot, delete the cluster and its PVCs, restore.

## Upstream sources

- [`disaster_recovery_for_shared_data_cluster_howto.md`](../upstream/starrocks-kubernetes-operator/doc/disaster_recovery_for_shared_data_cluster_howto.md)
- [`cluster_snapshot.md`](../upstream/starrocks/docs/en/administration/management/cluster_snapshot.md)
- [`charts/starrocks/values.yaml`](../upstream/starrocks-kubernetes-operator/helm-charts/charts/kube-starrocks/charts/starrocks/values.yaml), `starrocksCluster.disasterRecovery`
