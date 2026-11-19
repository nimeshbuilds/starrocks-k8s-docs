# 9. Security

A new cluster starts with an empty `root` password and plaintext connections. This guide covers closing those gaps and the pod-level controls the operator exposes.

## Checklist

1. Set the `root` password, and give the operator and pods access to it.
2. Create named users and roles. Do not hand out `root`.
3. Keep the FE service off public networks.
4. Turn on TLS for client connections if your policy needs it.
5. Use IAM roles through a ServiceAccount for cloud access, not static keys.
6. Run as non-root. Add a read-only root filesystem if required.
7. Pin and mirror images.
8. Scope the operator to the namespaces it needs.

## Root password

### Why the pods need it

StarRocks components run helper scripts that log in to FE as `root`, for example to register a node. Once `root` has a password, each component needs it in the `MYSQL_PWD` environment variable or those scripts fail.

### At install time, with Helm

Works on `helm install` only. It does nothing on `helm upgrade`.

```bash
kubectl -n starrocks create secret generic starrocks-root-password \
  --from-literal=password='<password>'
```

```yaml
# starrocks chart. Nest under `starrocks:` for kube-starrocks.
initPassword:
  enabled: true
  passwordSecret: starrocks-root-password   # key must be "password"
```

Notes:

- `password:` accepts plaintext in values. Prefer `passwordSecret`. If both are set, the secret wins.
- The chart runs a one-time Job. `initPassword.image` overrides its image, which otherwise is the FE image.
- If you installed with `initPassword`, keep that block in your values for every later upgrade. If you installed without it, never add it later.
- **Argo CD:** set `initPassword.isInstall: false` after the first sync. Argo CD applies rendered templates on every sync, so the Job would otherwise run again each time.

### After install, on any cluster

```sql
-- connected as root with the empty password
SET PASSWORD = PASSWORD('<password>');
```

```bash
kubectl -n starrocks create secret generic rootcredential \
  --from-literal=password='<password>'
```

```yaml
spec:
  starRocksFeSpec:
    feEnvVars:
      - name: MYSQL_PWD
        valueFrom: {secretKeyRef: {name: rootcredential, key: password}}
  starRocksBeSpec:
    beEnvVars:
      - name: MYSQL_PWD
        valueFrom: {secretKeyRef: {name: rootcredential, key: password}}
  starRocksCnSpec:
    cnEnvVars:
      - name: MYSQL_PWD
        valueFrom: {secretKeyRef: {name: rootcredential, key: password}}
```

Applying this rolls every component. Verify with:

```bash
kubectl -n starrocks exec sr-fe-0 -- sh -c 'echo ${MYSQL_PWD:+set}'
```

With Helm, add the same env blocks under `starrocksFESpec.feEnvVars`, `starrocksBeSpec.beEnvVars` and `starrocksCnSpec.cnEnvVars`. The chart can create the Secret from a top-level `secrets:` list, but that puts the password in your values file. Creating the Secret out of band is safer.

### Rotating the password

Change it in SQL, update the Secret, then restart the components so they read the new value. Environment variables from Secrets are read only at container start.

## Users, roles and privileges

StarRocks has its own role-based access control. Create users and grant roles in SQL:

```sql
CREATE USER 'analyst'@'%' IDENTIFIED BY '<password>';
CREATE ROLE readonly;
GRANT USAGE ON CATALOG hive_glue TO ROLE readonly;
SET CATALOG hive_glue;                                   -- grants below apply to this catalog
GRANT SELECT ON ALL TABLES IN ALL DATABASES TO ROLE readonly;
GRANT readonly TO USER 'analyst'@'%';
SET DEFAULT ROLE readonly TO 'analyst'@'%';
```

Table grants apply to the current catalog, so switch with `SET CATALOG` before granting on an external catalog. Authentication can also be delegated to LDAP and other providers, and FE supports SSL authentication.

Upstream references:

- [`administration/user_privs/`](../upstream/starrocks/docs/en/administration/user_privs/), including [`ssl_authentication.md`](../upstream/starrocks/docs/en/administration/user_privs/ssl_authentication.md)
- [`post_deployment_setup.md`](../upstream/starrocks/docs/en/deployment/manage_deployment/post_deployment_setup.md)

## TLS for client connections

FE can serve the MySQL protocol over TLS. The settings live in `fe.conf`:

| Setting | Meaning |
|---|---|
| `ssl_keystore_location` | Path to the keystore file |
| `ssl_keystore_password` | Keystore password |
| `ssl_key_password` | Password of the private key in the keystore |
| `ssl_force_secure_transport` | When `true`, FE rejects plaintext connections with error 5205 |

Mount the keystore from a Secret with the component's `secrets:` list and point `ssl_keystore_location` at it.

Two traps called out upstream:

- **`ssl_key_password` must equal `ssl_keystore_password`.** Recent JDKs create PKCS12 keystores, which do not support a separate key password. `keytool` only prints a warning. FE then starts and looks healthy but cannot read its key.
- **Test through the Service DNS name, not loopback.** FE exempts `127.0.0.1` from `ssl_force_secure_transport`, so a test from inside the FE pod against localhost succeeds in plaintext even when enforcement is on.

### TLS between the operator and FE

The operator opens its own MySQL connection to FE for maintenance statements such as `SHOW COMPUTE NODES`, `ALTER SYSTEM DROP COMPUTE NODE` and `DROP WAREHOUSE`. Control it with `--fe-ssl-mode`, or the Helm value `starrocksOperator.feSslMode`.

| Mode | Behaviour |
|---|---|
| `DISABLED` | Always plaintext. Fails against an FE that forces secure transport. |
| `PREFERRED` (default) | Encrypts when FE advertises SSL, plaintext otherwise |
| `REQUIRED` | Always encrypts. Fails if FE does not support SSL. |

- The operator never verifies the server certificate, in any mode. `REQUIRED` protects against passive eavesdropping, not an active man-in-the-middle.
- `VERIFY_CA` and `VERIFY_IDENTITY` are recognised names, but the operator refuses to start with either. An unknown or empty value also stops it.
- `PREFERRED` does not fall back to plaintext after a failed TLS handshake. It falls back only when FE does not advertise SSL at all. Use `DISABLED` as a temporary escape if the handshake cannot be negotiated.
- Changing the mode restarts the operator pod only.

```bash
helm upgrade starrocks-operator starrocks/operator --reuse-values \
  --set starrocksOperator.feSslMode=REQUIRED
# umbrella chart: --set operator.starrocksOperator.feSslMode=REQUIRED
```

## Cloud credentials

Prefer workload identity over static keys.

1. Create an IAM role with the object store and catalog permissions the cluster needs.
2. Bind it to a Kubernetes ServiceAccount. On EKS that is IRSA or EKS Pod Identity.
3. Set `serviceAccount` on **each component that touches the cloud**. FE and CN both need it for shared-data storage and for external catalogs.

```yaml
spec:
  starRocksFeSpec:
    serviceAccount: starrocks-sa
  starRocksCnSpec:
    serviceAccount: starrocks-sa
```

4. Tell StarRocks to use the SDK credential chain:
   - Shared-data storage: `aws_s3_use_aws_sdk_default_behavior = true` in `fe.conf`, or `"aws.s3.use_aws_sdk_default_behavior" = "true"` on the storage volume.
   - External catalogs: `"aws.s3.use_instance_profile" = "true"` and `"aws.glue.use_instance_profile" = "true"`, optionally with `aws.s3.iam_role_arn` and `aws.glue.iam_role_arn` to assume another role.

The top-level `spec.serviceAccount` is deprecated. Set it per component.

Minimum permissions to plan for:

| Purpose | Permissions |
|---|---|
| Shared-data storage bucket | Read, write, list and delete on the bucket and prefix |
| Data lake buckets, read only | `s3:GetObject`, `s3:ListBucket` |
| AWS Glue Data Catalog, read only | `glue:GetDatabase(s)`, `glue:GetTable(s)`, `glue:GetPartition(s)`, `glue:BatchGetPartition` |
| Writing to lake tables through StarRocks | Add the matching S3 write and Glue write actions |

Scope each to specific resources. The Data on EKS Terraform grants `s3:Get*`, `s3:List*` and `s3:*Object*` on its one bucket, as a reference point.

## Pod security

| Control | Field | Notes |
|---|---|---|
| Non-root | `runAsNonRoot: true` | Operator sets UID and GID 1000. Decide at install. Files written by root earlier become unreadable. |
| Read-only root filesystem | `readOnlyRootFilesystem: true` | Needs the artifacts-volume pattern in [Storage](06-storage.md#read-only-root-filesystem) |
| Capabilities | `capabilities.add` / `.drop` | For example drop `SYS_ADMIN`. Profiling tools may need `PERFMON` and `SYS_PTRACE`. |
| Sysctls | `sysctls` | Namespaced sysctls only |
| Private registry | `imagePullSecrets` | |
| Host aliases | `hostAliases` | Static `/etc/hosts` entries |

The operator's own pod defaults to non-root, no privilege escalation and a read-only root filesystem. Add `capabilities.drop: [ALL]` and a `seccompProfile` under `starrocksOperator.securityContext` if your admission policy requires them.

## Least privilege for the installer

The identity that runs `kubectl apply` or `helm install` needs these rights. The operator then uses its own ServiceAccount.

| API group | Resources |
|---|---|
| core | `secrets`, `serviceaccounts`, `configmaps` |
| `rbac.authorization.k8s.io` | `clusterroles`, `clusterrolebindings`, `roles`, `rolebindings` |
| `apps` | `deployments` |
| `apiextensions.k8s.io` | `customresourcedefinitions` |
| `starrocks.com` | `starrocksclusters`, `starrockswarehouses` |
| `batch` | `jobs` (for the init-password job) |
| `monitoring.coreos.com` | `servicemonitors` (only if you enable them) |

The ready-made ClusterRole is in [`least_permission_to_deploy_starrocks_howto.md`](../upstream/starrocks-kubernetes-operator/doc/least_permission_to_deploy_starrocks_howto.md). The operator's own permissions are in [`deploy/operator.yaml`](../upstream/starrocks-kubernetes-operator/deploy/operator.yaml).

To shrink the operator's reach, set `watchNamespace` so it gets a namespaced Role instead of a ClusterRole. See [Install the operator](02-install-operator.md#scoping-the-operator).

## Workload identity with SPIFFE

The operator can mount an ephemeral CSI volume, which is how the SPIFFE CSI driver delivers the workload API socket:

```yaml
starRocksFeSpec:
  storageVolumes:
    - name: spiffe-workload-api
      storageClassName: csi
      mountPath: /spiffe-workload-api
      readOnly: true
      csi:
        driver: csi.spiffe.io
        readOnly: true
```

Supported on FE, BE, CN and the FE proxy. The driver must already be installed. Details in [`mount_csi_volumes_howto.md`](../upstream/starrocks-kubernetes-operator/doc/mount_csi_volumes_howto.md).

## Secrets hygiene

- Keep passwords and keys in Secrets, referenced with `valueFrom` or mounted as files. Avoid putting them in `fe.conf`, which is a ConfigMap.
- Catalog and storage-volume credentials passed as SQL properties are stored in FE metadata. IAM roles avoid that.
- Protect the FE metadata volume and any cluster snapshots. They contain the catalog definitions.

## Auditing

FE writes an audit log of every statement to `fe.audit.log` in the FE log directory. Persist the FE log volume or ship logs to your log platform. Upstream also documents an audit loader that stores audit records in a table: [`audit_loader.md`](../upstream/starrocks/docs/en/administration/management/audit_loader.md).

## Upstream sources

- [`initialize_root_password_howto.md`](../upstream/starrocks-kubernetes-operator/doc/initialize_root_password_howto.md)
- [`change_root_password_howto.md`](../upstream/starrocks-kubernetes-operator/doc/change_root_password_howto.md)
- [`connect_to_ssl_enabled_fe_howto.md`](../upstream/starrocks-kubernetes-operator/doc/connect_to_ssl_enabled_fe_howto.md)
- [`least_permission_to_deploy_starrocks_howto.md`](../upstream/starrocks-kubernetes-operator/doc/least_permission_to_deploy_starrocks_howto.md)
- [`setup-starrocks-when-readOnlyRootFilesystem-is-true.md`](../upstream/starrocks-kubernetes-operator/doc/setup-starrocks-when-readOnlyRootFilesystem-is-true.md)
- [`administration/user_privs/`](../upstream/starrocks/docs/en/administration/user_privs/)
