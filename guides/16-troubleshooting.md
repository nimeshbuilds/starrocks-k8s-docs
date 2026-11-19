# 16. Troubleshooting

Problems you are likely to meet running StarRocks on Kubernetes, grouped by where they show up.

## First commands

```bash
kubectl -n starrocks get starrockscluster
kubectl -n starrocks describe starrockscluster <name>
kubectl -n starrocks get pods -o wide
kubectl -n starrocks describe pod <pod>
kubectl -n starrocks logs <pod>              # add -p for the previous container
kubectl -n starrocks logs deploy/kube-starrocks-operator
kubectl -n starrocks get events --sort-by=.lastTimestamp | tail -30
kubectl -n starrocks get pvc
```

If pod logs are empty, the component is writing to files. Read them in the pod, or set `LOG_CONSOLE=1`. See [Observability](12-observability.md#logs).

```bash
kubectl -n starrocks exec <fe-pod> -- tail -n 200 /opt/starrocks/fe/log/fe.log
kubectl -n starrocks exec <cn-pod> -- tail -n 200 /opt/starrocks/cn/log/cn.INFO
```

## Installing

| Symptom | Cause | Fix |
|---|---|---|
| `metadata.annotations: Too long: must have at most 262144 bytes` on `kubectl apply` | The object is too large for the last-applied annotation. Happens with the CRD and with large CRs. | `kubectl create -f` for a first install, `kubectl replace -f` for updates, or server-side apply |
| `no matches for kind "StarRocksCluster"` | CRD not installed | Apply the CRD first |
| `no matches for kind "StarRocksWarehouse"`, or the warehouse is ignored | Warehouse CRD missing, or the operator started before the CRD existed | Apply the CRD, then `kubectl rollout restart deployment kube-starrocks-operator` |
| Cluster object exists, nothing happens | Operator not running, watching another namespace, or the namespace is on its `denyList` | Check the operator pod and its `watchNamespace` and `denyList` |
| Two operators fighting over one cluster | More than one operator watching the same namespace | Set `watchNamespace` on each, or run one operator |
| Helm upgrade did not change the CRD | Helm does not upgrade existing CRDs | Apply the new CRD by hand |
| Root password job runs on every Argo CD sync | `initPassword.isInstall` still `true` | Set it to `false` after the first install |

## Pods will not start

| Symptom | Cause | Fix |
|---|---|---|
| `Pending`, no node | No capacity, or `nodeSelector`, affinity or tolerations match nothing | `kubectl describe pod`. Check the node autoscaler. |
| `Pending`, PVC unbound | StorageClass missing, CSI driver missing, or zone mismatch | `kubectl describe pvc` |
| `ImagePullBackOff` | Registry not reachable, wrong tag, or missing pull secret | Mirror images, fix the tag, set `imagePullSecrets` |
| FE `CrashLoopBackOff` right after start | Bad `fe.conf`, heap larger than the memory limit, or metadata volume not writable | Read `fe.out` and `fe.log`. Check `-Xmx` against the limit. |
| FE restarts during a long start | Startup probe expired while FE replayed metadata | Raise `startupProbeFailureSeconds` |
| FE stops with a disk message | Less than 5 Gi free on the metadata volume | Grow the volume. Size it at 10 Gi or more from the start. |
| BE or CN `CrashLoopBackOff` | Cannot reach FE, wrong `MYSQL_PWD`, bad config, or out of memory | Read `be.out` or `cn.out`. Check the password variable. |
| Permission denied on a volume after enabling `runAsNonRoot` | Files were created as root earlier | Fix ownership, or recreate. Choose `runAsNonRoot` at install. |
| Will not start with `readOnlyRootFilesystem` | StarRocks writes inside its install directory | Use the artifacts-volume pattern in [Storage](06-storage.md#read-only-root-filesystem) |
| BE and CN never appear | They start after an FE is ready | Fix FE first |

## Nodes do not register

| Symptom | Cause | Fix |
|---|---|---|
| CN or BE pod is `Running` but missing from `SHOW COMPUTE NODES` or `SHOW BACKENDS` | The pod could not log in to FE to add itself | Usually the root password. Inject `MYSQL_PWD` into every component. See [Security](09-security.md#root-password). |
| It worked until the root password was changed | Components still have no password, or the old one | Update the Secret and restart the components |
| Nodes listed with `Alive = false` after scale-in | Stale registrations | `ALTER SYSTEM DROP COMPUTE NODE "<host>:9050";` |
| FE count in `SHOW FRONTENDS` differs from the pod count | A failed or half-done FE scale-in | Follow the FE scale-in procedure exactly. See [Scaling](07-scaling-and-autoscaling.md#scaling-in-fe). |

## Connecting

| Symptom | Cause | Fix |
|---|---|---|
| Cannot connect from outside the cluster | FE service is `ClusterIP` | Port-forward, or change the service type. See [Networking](08-networking-and-access.md). |
| Error 5205, `Connections using insecure transport are prohibited` | FE has `ssl_force_secure_transport = true` and the client is not using TLS | Enable TLS on the client. For the operator, set `feSslMode`. |
| Operator log fills with error 5205 | Operator `feSslMode` is `DISABLED` against an FE that forces TLS | Use `PREFERRED` or `REQUIRED` |
| Operator fails against an FE with TLS on, in `REQUIRED` mode, no clear reason | `ssl_key_password` differs from `ssl_keystore_password`, so FE cannot read its key | Make the two passwords equal and recreate the keystore |
| TLS enforcement seems not to work when tested from the FE pod | FE exempts `127.0.0.1` | Test through the Service DNS name |
| Stream Load fails from outside the cluster after a redirect | The 307 redirect points at a private pod address | Use the FE proxy on port 8080 |
| `Access denied` for `root` | Password was set | Use the password |

## Shared-data and object storage

| Symptom | Cause | Fix |
|---|---|---|
| FE starts, `CREATE TABLE` fails with a storage error | No default storage volume, or it cannot reach the bucket | `SHOW STORAGE VOLUMES;`. Create and set a default volume, or fix `aws_s3_*` in `fe.conf`. |
| Access denied to S3 | The pod's ServiceAccount has no role, or `serviceAccount` is set on CN but not FE | Set it on both. Check the role's policy and trust. |
| Works with access keys, fails with roles | StarRocks was not told to use the SDK credential chain | `aws_s3_use_aws_sdk_default_behavior = true` |
| Timeouts to S3 or Glue from private subnets | No route | Add VPC endpoints or a NAT path |
| Changed `aws_s3_path` in `fe.conf`, nothing changed | The built-in volume is created from the config only at first start | Alter or recreate the storage volume in SQL |

More: [`shared_data_faq.md`](../upstream/starrocks/docs/en/faq/shared_data_faq.md).

## Data lake queries

| Symptom | Cause | Fix |
|---|---|---|
| Catalog shows no databases | FE lacks Glue permission, wrong region, or no network path | Check FE logs and the role |
| Databases list, queries fail on file access | CN or BE lacks S3 permission | Set the ServiceAccount on CN and BE |
| New files or partitions are missing from results | Metadata cache | `REFRESH EXTERNAL TABLE`, or tune the cache. See [Data lake](10-data-lake-on-s3-and-glue.md#metadata-caching-and-freshness). |
| First query on a table is slow to plan | Cold metadata cache, many partitions, many small files | Filter on partitions. Compact small files. |
| Queries slower with the data cache on | Cache volume slower than object storage | Use faster disks, or turn off the disk cache |
| Cache never seems to be hit | Queries read different cold data each time, or the cache is too small | Check `DataCacheReadBytes` in the profile |
| Query killed with a resource group message | A big-query limit fired | Add a partition filter, or raise the limit for that group |
| Out of memory on large joins or aggregations | No spill | Enable spill. See [Resource management](11-resource-management.md#spill-to-disk). |

More: [`datalake_faq.md`](../upstream/starrocks/docs/en/data_source/datalake_faq.md), [`data_cache_troubleshooting.md`](../upstream/starrocks/docs/en/data_source/data_cache/data_cache_troubleshooting.md).

## Scaling

| Symptom | Cause | Fix |
|---|---|---|
| CN count keeps snapping back | `replicas` is set together with `autoScalingPolicy`, or together with KEDA | Remove `replicas` from the CN spec |
| HPA shows `<unknown>` targets | metrics-server missing, or pods have no resource requests | Install metrics-server. Set requests. |
| HPA never scales in | `scaleDown.selectPolicy: Disabled`, or memory utilization stays high | Check the behavior block. Prefer CPU as the signal. |
| HPA left behind after removing the policy | Old operator | Upgrade to 1.11.0 or later |
| PVCs pile up after CN scale-in | No retention policy | `persistentVolumeClaimRetentionPolicy.whenScaled: Delete` |
| Queries fail after lowering BE `replicas` | BEs were removed without decommissioning | Set `replicas` back, then follow the decommission procedure |
| FE scale-in from 3 to 1 fails | Not supported | Stay at 3, or rebuild |
| KEDA does not scale from zero | Prometheus unreachable from KEDA, wrong label in the query, or FE metrics not scraped | `kubectl describe scaledobject`. Test the query in Prometheus. |
| New CN pods wait minutes | Node provisioning | Raise `minReplicas`, or keep warm capacity |

## Upgrades and rollouts

| Symptom | Cause | Fix |
|---|---|---|
| Errors between FE and BE or CN after an upgrade | Components upgraded in the wrong order | BE and CN first, then FE. Reverse for downgrade. |
| A bad FE image took BE and CN down with it | BE and CN proceeded before FE was fully rolled out | `waitForFullRollout: true` |
| Rollout stuck on one pod | New pod not ready | Read its logs. A StatefulSet rollout waits for readiness. |
| Pods restarted when only the operator was upgraded | New operator generates a different pod template | Expected sometimes. Upgrade the operator in a window. |
| Different builds across pods | Moving image tag | Pin exact tags |
| Queries cut off during rollouts | Grace period too short | Raise `terminationGracePeriodSeconds`. Set `min_graceful_exit_time_second`. |

## Configuration

| Symptom | Cause | Fix |
|---|---|---|
| Config change had no effect | Static parameter, pods not restarted | Roll the component |
| Runtime setting vanished | Set with SQL only, lost at restart | Also put it in the ConfigMap |
| Helm `config` ignored | `configyaml` is non-empty and replaces it | Use one of the two |
| Large number became `1.07e+10` | YAML number in `configyaml` | Quote it |
| Logs go to the wrong place after moving a mount | Log directory settings not updated | Set `sys_log_dir`, and for FE also `dump_log_dir` and `audit_log_dir` |
| Wrong time zone in logs | Chart default `timeZone: Asia/Shanghai` | Set `timeZone` |
| FE proxy cannot resolve names | Cluster DNS service is not `kube-dns.kube-system`, or the DNS suffix is not `cluster.local` | Set `resolver` on the proxy and `dnsDomainSuffix` on the operator |

## Disaster recovery

| Symptom | Cause | Fix |
|---|---|---|
| Restore does not start | `enabled` not `true`, `generation` not higher than `observedGeneration`, or no ConfigMap mounted with `subPath: cluster_snapshot.yaml` | Fix and raise `generation` |
| Restore FE never becomes ready | Wrong snapshot path, no access to the bucket, or leftover metadata on the volume | Read the FE log. Start from empty PVCs. |
| Stuck in `doing` | Restore still running, or failed | The FE has no liveness probe during restore. Check its log. |

## Getting more detail

- Operator debug logs: add `--zap-log-level 4` to the operator arguments.
- Query problems: the query profile and `EXPLAIN ANALYZE`.
- FE memory: [`fe_memory_troubleshooting.md`](../upstream/starrocks/docs/en/best_practices/fe_memory_troubleshooting.md) and [`fe_mem_faq.md`](../upstream/starrocks/docs/en/faq/fe_mem_faq.md).
- Operations FAQ: [`operation_maintenance_faq.md`](../upstream/starrocks/docs/en/faq/operation_maintenance_faq.md) and [`Deploy_faq.md`](../upstream/starrocks/docs/en/faq/Deploy_faq.md).
- Resource isolation FAQ: [`resource_isolation_faq.md`](../upstream/starrocks/docs/en/faq/resource_isolation_faq.md).
- Error codes: [`Error_code.md`](../upstream/starrocks/docs/en/sql-reference/Error_code.md).

## Upstream sources

- FAQ section of [`deploy_starrocks_with_operator_howto.md`](../upstream/starrocks-kubernetes-operator/doc/deploy_starrocks_with_operator_howto.md)
- Troubleshooting section of [`infra.md`](../upstream/data-on-eks/website/docs/datastacks/databases/starrocks-on-eks/infra.md)
- [`faq/`](../upstream/starrocks/docs/en/faq/)
