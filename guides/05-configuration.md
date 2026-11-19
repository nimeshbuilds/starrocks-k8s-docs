# 5. Configuration

How to set StarRocks configuration on Kubernetes: config files, environment variables, extra mounts, and what triggers a restart.

## The three config files

| Component | File | Path in the container | Default upstream template |
|---|---|---|---|
| FE | `fe.conf` | `/opt/starrocks/fe/conf/fe.conf` | https://github.com/StarRocks/starrocks/blob/main/conf/fe.conf |
| BE | `be.conf` | `/opt/starrocks/be/conf/be.conf` | https://github.com/StarRocks/starrocks/blob/main/conf/be.conf |
| CN | `cn.conf` | `/opt/starrocks/cn/conf/cn.conf` | https://github.com/StarRocks/starrocks/blob/main/conf/cn.conf |

The images ship with defaults. A ConfigMap you reference replaces the file. In the container the file is a symlink into `/etc/starrocks/<component>/conf/`, where the ConfigMap is mounted.

The built-in FE default heap is `-Xmx8192m`. That is too large for a small FE pod and too small for a busy one. Always set it to fit the pod's memory limit.

## With a manifest: `configMapInfo`

```yaml
spec:
  starRocksFeSpec:
    configMapInfo:
      configMapName: sr-fe-cm
      resolveKey: fe.conf
  starRocksCnSpec:
    configMapInfo:
      configMapName: sr-cn-cm
      resolveKey: cn.conf
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: sr-fe-cm
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
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: sr-cn-cm
data:
  cn.conf: |
    sys_log_level = INFO
    thrift_port = 9060
    webserver_port = 8040
    heartbeat_service_port = 9050
    brpc_port = 8060
```

You can also build the ConfigMap from a file:

```bash
kubectl -n starrocks create configmap sr-fe-cm --from-file=fe.conf
```

Your file replaces the default completely. Keep the port and log lines shown above, then add your own settings.

## With Helm: `config` and `configyaml`

```yaml
starrocksFESpec:
  config: |
    LOG_DIR = ${STARROCKS_HOME}/log
    ...
    min_graceful_exit_time_second = 25

starrocksCnSpec:
  # A map alternative. When non-empty it replaces `config` entirely.
  configyaml:
    sys_log_level: INFO
    brpc_socket_max_unwritten_bytes: "10737418240"   # quote large numbers
```

- The chart creates the ConfigMaps and stamps a config hash annotation on the pods, so a config change rolls the component on `helm upgrade`.
- With `configyaml`, quote numbers so YAML does not turn them into scientific notation.
- The chart's default `fe.conf` adds `min_graceful_exit_time_second = 25`. See [Graceful shutdown](#graceful-shutdown).

## Port names in `be.conf` and `cn.conf`

From StarRocks 3.1 the documentation uses `be_port` and `be_http_port`. The older names `thrift_port` and `webserver_port` still work, and the operator chart defaults still use them. Use one naming style per file.

## Environment variables

```yaml
starRocksFeSpec:
  feEnvVars:
    - name: TZ
      value: UTC
    - name: LOG_CONSOLE
      value: "1"
    - name: MYSQL_PWD
      valueFrom:
        secretKeyRef: {name: rootcredential, key: password}
```

| Variable | Effect |
|---|---|
| `TZ` | Container time zone. The Helm chart sets it from `timeZone`, which defaults to `Asia/Shanghai`. |
| `LOG_CONSOLE=1` | Send component logs to stdout so `kubectl logs` and log agents can read them |
| `MYSQL_PWD` | The `root` password, needed by the component scripts once a password is set. See [Security](09-security.md#root-password). |
| `STARROCKS_ROOT` | Alternate install root, used with a read-only root filesystem |

Use `feEnvVars`, `beEnvVars` and `cnEnvVars` in the CR. Warehouses use `envVars`.

## Mount extra ConfigMaps and Secrets

For files such as a Hadoop `core-site.xml`, a Kerberos keytab, a truststore, or `cluster_snapshot.yaml`:

```yaml
starRocksFeSpec:
  configMaps:
    - name: hadoop-conf
      mountPath: /etc/hadoop-conf
    - name: extra-conf
      mountPath: /opt/starrocks/fe/conf/core-site.xml
      subPath: core-site.xml          # one file, other files in the directory are kept
  secrets:
    - name: keystore
      mountPath: /etc/starrocks-tls
```

The ConfigMap or Secret must exist before the cluster is applied. With Helm, the chart can create them for you from top-level `configMaps:` and `secrets:` lists.

Operator-created volumes for these mounts get a hash suffix in their names. If a sidecar or init container has to mount the same volume by name, start the operator with `--volume-name-with-hash=false`.

## Custom entrypoint

CR:

```yaml
starRocksFeSpec:
  command: ["bash", "-c"]
  args:
    - echo "pre-start work" && exec /opt/starrocks/fe_entrypoint.sh $FE_SERVICE_NAME
```

Helm:

```yaml
starrocksFESpec:
  entrypoint:
    script: |
      #! /bin/bash
      echo "pre-start work"
      exec /opt/starrocks/fe_entrypoint.sh $FE_SERVICE_NAME
```

The default entrypoints are `/opt/starrocks/fe_entrypoint.sh`, `be_entrypoint.sh` and `cn_entrypoint.sh`, each called with `$FE_SERVICE_NAME`. With Helm, the script is stored in a ConfigMap named `<cluster>-<component>-entrypoint-script` and mounted at `/etc/starrocks/entrypoint.sh`. Changing it restarts the pods.

## Static and dynamic parameters

StarRocks has two kinds of settings.

- **Static** parameters are read at startup. Change them in the ConfigMap and let the component roll.
- **Dynamic** parameters can be changed at runtime with SQL. They do not survive a restart unless you also put them in the config file.

```sql
-- FE dynamic parameter
ADMIN SET FRONTEND CONFIG ("key" = "value");

-- BE or CN dynamic parameter, all nodes
UPDATE information_schema.be_configs SET value = "value" WHERE name = "key";

-- Session and global variables
SET GLOBAL some_variable = value;
```

On Kubernetes, treat the ConfigMap as the source of truth. A runtime change that is not written back will disappear at the next pod restart.

Parameter references:

- FE: [`administration/configuration/FE_parameters/`](../upstream/starrocks/docs/en/administration/configuration/FE_parameters/)
- BE and CN: [`administration/configuration/BE_parameters/`](../upstream/starrocks/docs/en/administration/configuration/BE_parameters/)
- System variables: [`sql-reference/System_variable.md`](../upstream/starrocks/docs/en/sql-reference/System_variable.md)

## Settings you are likely to touch

| Where | Setting | Why |
|---|---|---|
| `fe.conf` | `JAVA_OPTS` `-Xmx` | Fit the FE heap to the pod memory limit |
| `fe.conf` | `run_mode`, `cloud_native_meta_port`, `aws_s3_*`, `enable_load_volume_from_conf` | Shared-data mode |
| `fe.conf` | `min_graceful_exit_time_second` | Graceful shutdown window |
| `fe.conf` | `ssl_keystore_location`, `ssl_keystore_password`, `ssl_key_password`, `ssl_force_secure_transport` | TLS for MySQL connections |
| `fe.conf` | `query_timeout`, `max_connection` | Client limits |
| `cn.conf` / `be.conf` | `storage_root_path` | Data or cache directories, separated by `;` |
| `cn.conf` / `be.conf` | `datacache_enable`, `block_cache_enable`, `datacache_mem_size`, `datacache_disk_size` | Data cache |
| `cn.conf` / `be.conf` | `spill_local_storage_dir` | Where spilled intermediate results go |
| `cn.conf` / `be.conf` | `sys_log_dir`, `sys_log_level` | Logging |

## Graceful shutdown

When a pod is deleted, Kubernetes runs the operator's `preStop` hook, then waits up to `terminationGracePeriodSeconds`.

- FE waits `min_graceful_exit_time_second` before refusing new requests. This needs StarRocks 3.4.2 or later.
- With the default readiness probe (period 5 seconds, threshold 3), a pod can take up to about 20 seconds to be marked not ready. The Helm chart sets `min_graceful_exit_time_second = 25` so the FE keeps serving until traffic has moved away. Do the same in hand-written `fe.conf`.
- Keep `terminationGracePeriodSeconds` longer than your longest acceptable in-flight query. The Helm default is 120.

Upstream reference: [`graceful_exit.md`](../upstream/starrocks/docs/en/administration/management/graceful_exit.md).

## What restarts pods

| Change | Effect |
|---|---|
| Image, resources, env vars, probes, volumes, scheduling fields | Rolling restart of that component |
| Config through Helm `config` or `configyaml` | Rolling restart, driven by the config hash annotation |
| Editing a ConfigMap referenced by `configMapInfo` in a hand-written manifest | Do not count on a restart. StarRocks does not reload static parameters from a changed file. If the pods do not roll, restart the component yourself, for example by changing a pod annotation in the spec. |
| `replicas` | Scale only, no restart |
| Operator flags | Operator pod restart only |

## Upstream sources

- [`deploy_a_starrocks_cluster_with_custom_configurations.yaml`](../upstream/starrocks-kubernetes-operator/examples/starrocks/deploy_a_starrocks_cluster_with_custom_configurations.yaml)
- [`mount_external_configmaps_or_secrets_howto.md`](../upstream/starrocks-kubernetes-operator/doc/mount_external_configmaps_or_secrets_howto.md)
- [`logging_and_related_configurations_howto.md`](../upstream/starrocks-kubernetes-operator/doc/logging_and_related_configurations_howto.md)
- [`charts/starrocks/values.yaml`](../upstream/starrocks-kubernetes-operator/helm-charts/charts/kube-starrocks/charts/starrocks/values.yaml)
- [`administration/configuration/`](../upstream/starrocks/docs/en/administration/configuration/)
