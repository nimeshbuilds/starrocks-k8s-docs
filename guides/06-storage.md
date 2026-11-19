# 6. Storage

What each component stores, how to give it volumes, and the special cases.

## What needs a disk

| Component | Path | Contents | Persistence needed |
|---|---|---|---|
| FE | `/opt/starrocks/fe/meta` | Cluster metadata | **Yes.** Losing it on a single-FE cluster loses the cluster. |
| FE | `/opt/starrocks/fe/log` | `fe.out`, `fe.log`, `fe.warn.log`, audit and GC logs | Recommended |
| BE | `/opt/starrocks/be/storage` | Table data | **Yes** |
| BE | `/opt/starrocks/be/log` | `be.out`, `be.INFO`, `be.WARNING` | Recommended |
| CN | `/opt/starrocks/cn/storage` | Data cache | No. It is a cache. |
| CN | `/opt/starrocks/cn/log` | `cn.out`, `cn.INFO`, `cn.WARNING` | Recommended |
| BE / CN | `/opt/starrocks/<be or cn>/spill` | Spilled intermediate results, if spill is enabled | No |

If you declare no volumes, the operator uses `emptyDir` for everything. A pod restart then wipes FE metadata and BE data.

The FE stops if free space on the metadata volume falls below 5 Gi. Give it at least 10 Gi. Upstream sizing guidance is 100 GB.

## Declaring volumes in the CR

```yaml
starRocksFeSpec:
  storageVolumes:
    - name: fe-meta
      storageClassName: gp3          # omit to use the default StorageClass
      storageSize: 100Gi
      mountPath: /opt/starrocks/fe/meta
    - name: fe-log
      storageSize: 10Gi
      mountPath: /opt/starrocks/fe/log
```

- The operator creates one PVC per volume per pod, named `<volume-name>-<pod-name>`. Do not create the PVCs yourself.
- The StorageClass must already exist.
- Volume fields cannot be changed after the cluster is created.

## Declaring volumes with Helm

```yaml
starrocksFESpec:
  storageSpec:
    name: fe                    # required for persistence. Empty means emptyDir.
    storageClassName: gp3
    storageSize: 100Gi          # metadata
    logStorageSize: 10Gi        # 0Gi disables the log PVC
    # storageMountPath, logStorageClassName, logMountPath are optional

starrocksBeSpec:
  storageSpec:
    name: be
    storageClassName: gp3
    storageSize: 1Ti
    storageCount: 1             # number of data volumes
    logStorageSize: 10Gi
    spillStorageSize: 0Gi       # set above 0 to create a spill PVC

starrocksCnSpec:
  storageSpec:
    name: cn
    storageSize: 500Gi
    logStorageSize: 20Gi
```

Rules the chart enforces or documents:

- You must set `name` when you set `storageClassName`.
- `hostPath` is not allowed as a `storageClassName` in `storageSpec`. Use the separate `hostPaths:` list.
- If you change a mount path away from its default, add the matching setting to the config: `storage_root_path` for data, `sys_log_dir` for BE and CN logs, and `dump_log_dir`, `sys_log_dir` and `audit_log_dir` for FE logs.
- For a spill PVC, add `spill_local_storage_dir=/opt/starrocks/cn/spill` (or the BE path) to the config.
- Once set, `storageSpec` fields cannot be modified.

## Special storage classes

Three `storageClassName` values do not create PVCs:

| Value | Behaviour | Typical use |
|---|---|---|
| `emptyDir` | Pod-lifetime scratch space | `/tmp`, artifacts directory |
| `hostPath` | A directory on the node. Needs the `hostPath` field. Data stays on that node only. | CN cache on a local NVMe mount |
| `csi` | An ephemeral inline CSI volume. Needs the `csi` field. | SPIFFE workload API socket |

`storageSize` is ignored for `emptyDir` and `hostPath`.

```yaml
starRocksCnSpec:
  storageVolumes:
    - name: cn-cache
      storageClassName: hostPath
      hostPath:
        path: /mnt/nvme/starrocks
      mountPath: /opt/starrocks/cn/storage
```

When you use `hostPath` for a cache, add pod anti-affinity so two CN pods never share a node, and expect the cache to be empty after a pod moves to another node.

Helm equivalents are the `emptyDirs:`, `hostPaths:` and `csiVolumes:` lists on each component.

CSI validation errors:

| Configuration | Error |
|---|---|
| `storageClassName: csi` with no `csi` block or an empty driver | `csi is required if storageClassName is csi, and csi.driver must not be empty` |
| `csi` and `hostPath` on the same volume | `csi and hostPath can not be set at the same time` |
| `csi` with another `storageClassName` | `if csi is set, storageClassName must be empty or "csi"` |

## CN cache disks

In a shared-data cluster, and for external catalog queries, the CN local disk holds the data cache. Table data itself is in object storage. You have four choices.

| Option | How | Trade-off |
|---|---|---|
| No disk cache | Leave out the storage volume and set `storage_root_path =` (empty) in `cn.conf` | Every read goes to object storage. Simplest. Reasonable when queries mostly touch cold data or CNs scale in and out often. |
| `emptyDir` | Default when no volume is declared | Cache lives on the node's ephemeral storage and is lost on pod restart |
| Network block PVC | `storageVolumes` with a StorageClass | Survives pod restarts. Cache speed is capped by the volume's IOPS and throughput, which can be slower than reading object storage directly. Provision performance explicitly if you choose this. |
| Local NVMe | `hostPath`, or a local-volume StorageClass | Fastest. Cache is lost when the node goes away. |

Upstream guidance on the cache medium is to use high-performance local disks such as NVMe, and to add disks if a single disk is slow.

Facts worth knowing:

- In shared-data mode the cache directory is `<storage_root_path>/starlet_cache`.
- `storage_root_path` accepts several directories separated by `;`.
- The data cache is on by default (`datacache_enable = true`). If you do not want a disk cache on a slow volume, turn it off or cap it rather than leaving it to grow. See [Data lake on S3 and Glue](10-data-lake-on-s3-and-glue.md#data-cache).
- Cached data on disk is reused after a CN restart when the volume persists.

The AWS Data on EKS shared-data example sets `storage_root_path = /mnt/k8s-disks` on NVMe-backed nodes and declares no volume for it. See [EKS reference](15-eks-reference.md).

## Multiple data volumes

CR:

```yaml
starRocksBeSpec:
  storageVolumes:
    - {name: be0-data, storageClassName: gp3, storageSize: 500Gi, mountPath: /opt/starrocks/be/storage0}
    - {name: be1-data, storageClassName: gp3, storageSize: 500Gi, mountPath: /opt/starrocks/be/storage1}
    - {name: be-log,   storageSize: 10Gi, mountPath: /opt/starrocks/be/log}
```

plus in `be.conf`:

```
storage_root_path = /opt/starrocks/be/storage0;/opt/starrocks/be/storage1
```

Helm:

```yaml
starrocksBeSpec:
  storageSpec:
    name: be-storage
    storageCount: 2          # mounts .../storage0 and .../storage1
    storageSize: 500Gi       # per volume
  config: |
    ...
    storage_root_path = /opt/starrocks/be/storage0;/opt/starrocks/be/storage1
```

The chart cannot give each volume a different class or size. If you need that, render the chart with `helm template`, edit the `StarRocksCluster` it produces, and apply that instead.

## PVC retention

By default PVCs outlive the pods and the cluster. To have Kubernetes delete them:

```yaml
starRocksCnSpec:
  persistentVolumeClaimRetentionPolicy:
    whenDeleted: Delete     # all components
    whenScaled: Delete      # CN only
```

- `whenDeleted: Delete` removes PVCs when the StatefulSet is deleted.
- `whenScaled: Delete` removes a CN's PVCs when it is scaled in. Use it with autoscaling so cache volumes do not pile up.
- `whenScaled` is not supported for FE or BE.
- Never set `whenDeleted: Delete` on FE metadata or BE data unless losing them is acceptable.

## Read-only root filesystem

StarRocks writes inside its install directory (pid files, plugins, UDFs, spill, a config symlink), so `readOnlyRootFilesystem: true` needs a writable copy. Requires operator 1.9.9 or later.

The pattern:

1. Mount an `emptyDir` at `/opt/starrocks-artifacts`.
2. Override the command to copy `/opt/starrocks/*` there and run the entrypoint from the copy.
3. Set `STARROCKS_ROOT=/opt/starrocks-artifacts`.
4. Mount data and log volumes under the new root, using the exact volume names the operator recognises: `fe-meta`, `fe-log`, `be-storage`, `be-log`.

```yaml
starRocksFeSpec:
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  storageVolumes:
    - {name: fe-artifacts, storageClassName: emptyDir, mountPath: /opt/starrocks-artifacts}
    - {name: fe-meta, storageSize: 100Gi, mountPath: /opt/starrocks-meta}
    - {name: fe-log,  storageSize: 10Gi,  mountPath: /opt/starrocks-log}
  command: ["bash", "-c"]
  args:
    - cp -r /opt/starrocks/* /opt/starrocks-artifacts && exec /opt/starrocks-artifacts/fe_entrypoint.sh $FE_SERVICE_NAME
  feEnvVars:
    - {name: STARROCKS_ROOT, value: /opt/starrocks-artifacts}
```

The full FE, BE and Helm versions, including the matching config changes, are in [`setup-starrocks-when-readOnlyRootFilesystem-is-true.md`](../upstream/starrocks-kubernetes-operator/doc/setup-starrocks-when-readOnlyRootFilesystem-is-true.md).

## Expanding a volume

The operator does not resize PVCs, and volume fields in the spec are immutable. If the StorageClass has `allowVolumeExpansion: true`, expand the PVCs directly with `kubectl patch pvc`. New pods will still be created at the size in the spec, so plan the initial size with headroom. For BE, adding nodes or adding a data volume at install time is the supported way to grow.

## Upstream sources

- [`mount_persistent_volume_howto.md`](../upstream/starrocks-kubernetes-operator/doc/mount_persistent_volume_howto.md)
- [`use_multiple_volumes_how_to.md`](../upstream/starrocks-kubernetes-operator/doc/use_multiple_volumes_how_to.md)
- [`mount_csi_volumes_howto.md`](../upstream/starrocks-kubernetes-operator/doc/mount_csi_volumes_howto.md)
- [`setup-starrocks-when-readOnlyRootFilesystem-is-true.md`](../upstream/starrocks-kubernetes-operator/doc/setup-starrocks-when-readOnlyRootFilesystem-is-true.md)
- [`deploy_a_starrocks_cluster_with_persistent_storage.yaml`](../upstream/starrocks-kubernetes-operator/examples/starrocks/deploy_a_starrocks_cluster_with_persistent_storage.yaml)
- [`data_cache.md`](../upstream/starrocks/docs/en/data_source/data_cache/data_cache.md)
- [`plan_cluster.md`](../upstream/starrocks/docs/en/deployment/preparation/plan_cluster.md)
