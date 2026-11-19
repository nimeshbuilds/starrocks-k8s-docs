# 2. Install the operator

The operator can be installed with plain manifests or with Helm. Pick one and stay with it for the life of the installation.

## Prerequisites

- Kubernetes 1.23 or later
- `kubectl` with permission to create CRDs, cluster roles and deployments. The minimum role is in [Security](09-security.md#least-privilege-for-the-installer).
- Helm 3.0 or later, if you use the Helm path
- Network access from the cluster to your image registry

## What gets installed

| Object | Default name | Notes |
|---|---|---|
| CRD | `starrocksclusters.starrocks.com` | Required |
| CRD | `starrockswarehouses.starrocks.com` | Only needed for warehouses |
| Namespace | `starrocks` | Manifest path only |
| ServiceAccount | `starrocks` | |
| ClusterRole and ClusterRoleBinding | `kube-starrocks-operator` | Cluster-wide, because the operator watches all namespaces by default |
| Role and RoleBinding | `cn-leader-election-role`, `cn-leader-election-rolebinding` | Leader election |
| Deployment | `kube-starrocks-operator` | One replica, container `manager` |

## Option A: plain manifests

### 1. Apply the CRD

```bash
kubectl apply -f https://raw.githubusercontent.com/StarRocks/starrocks-kubernetes-operator/main/deploy/starrocks.com_starrocksclusters.yaml
```

A copy is in this repository at [`upstream/starrocks-kubernetes-operator/deploy/starrocks.com_starrocksclusters.yaml`](../upstream/starrocks-kubernetes-operator/deploy/starrocks.com_starrocksclusters.yaml).

If `kubectl apply` fails with `metadata.annotations: Too long: must have at most 262144 bytes`, the CRD is too large for the last-applied annotation. Use `kubectl create -f` for a first install and `kubectl replace -f` for updates.

### 2. Apply the operator

```bash
kubectl apply -f https://raw.githubusercontent.com/StarRocks/starrocks-kubernetes-operator/main/deploy/operator.yaml
```

This installs into the `starrocks` namespace and watches every namespace.

To use a different namespace, download the file, replace every `namespace: starrocks`, then apply your copy:

```bash
curl -O https://raw.githubusercontent.com/StarRocks/starrocks-kubernetes-operator/main/deploy/operator.yaml
# edit operator.yaml
kubectl apply -f operator.yaml
```

For production, take the manifests from a tagged release instead of `main`, so the CRD and the operator image match. Releases are at https://github.com/StarRocks/starrocks-kubernetes-operator/releases.

### 3. Check it

```bash
kubectl -n starrocks get pods
```

The operator pod should be `Running` and `1/1` ready.

### Operator flags in the manifest

| Flag | Default | Meaning |
|---|---|---|
| `--leader-elect` | set | Leader election between operator replicas |
| `--zap-time-encoding=iso8601` | set | Log timestamp format |
| `--zap-encoder=console` | set | Log encoder |
| `--zap-log-level 4` | not set | Debug logging |
| `--volume-name-with-hash=true` | `true` | Adds a hash suffix to the volume names of operator-created ConfigMap and Secret mounts. Set to `false` if sidecars or init containers need to mount the same volume by a predictable name. |
| `--fe-ssl-mode=PREFERRED` | `PREFERRED` | TLS mode for the operator's own MySQL connection to FE. See [Security](09-security.md#tls-between-the-operator-and-fe). |

## Option B: Helm

### Add the chart repository

```bash
helm repo add starrocks https://starrocks.github.io/starrocks-kubernetes-operator
helm repo update starrocks
helm search repo starrocks
```

### The charts

| Chart | Installs | Use when |
|---|---|---|
| `starrocks/kube-starrocks` | Operator and one cluster. It is an umbrella over the two subcharts below. | You want one release for everything |
| `starrocks/operator` | Operator only | You manage clusters separately, or run several clusters |
| `starrocks/starrocks` | One `StarRocksCluster` | The operator is already installed |
| `starrocks/warehouse` | One `StarRocksWarehouse` | Enterprise warehouses |

Values for the umbrella chart are nested: operator values under `operator:` and cluster values under `starrocks:`. The same keys sit at the top level when you install a subchart directly.

### Install the operator only

```bash
helm install starrocks-operator starrocks/operator \
  --namespace starrocks --create-namespace
```

### Install operator and cluster together

```bash
helm show values starrocks/kube-starrocks > values.yaml
# edit a copy named my-values.yaml
helm install starrocks starrocks/kube-starrocks \
  --namespace starrocks --create-namespace \
  -f my-values.yaml
```

With no values file this deploys one FE and one BE. That is a smoke test, not a usable cluster.

### Operator chart values

| Value | Default | Meaning |
|---|---|---|
| `global.rbac.create` | `true` | Create the ServiceAccount, ClusterRole and binding. Setting this to `false` later deletes them. |
| `global.rbac.serviceAccount.name` | `starrocks` | ServiceAccount name |
| `global.rbac.serviceAccount.annotations` | `{}` | For example an IAM role annotation |
| `timeZone` | `Asia/Shanghai` | Sets `TZ` on the operator pod. Change it. |
| `nameOverride` | `kube-starrocks` | Resource name prefix |
| `starrocksOperator.enabled` | `true` | Deploy the operator |
| `starrocksOperator.image.repository` / `.tag` | `starrocks/operator` / `v1.11.8` | Operator image |
| `starrocksOperator.imagePullPolicy` | `Always` | |
| `starrocksOperator.replicaCount` | `1` | |
| `starrocksOperator.resources` | 500m CPU, 400Mi to 800Mi memory | |
| `starrocksOperator.securityContext` | non-root, no privilege escalation, read-only root filesystem | Add `capabilities.drop` and `seccompProfile` if your policy needs them |
| `starrocksOperator.imagePullSecrets` | `[]` | |
| `starrocksOperator.nodeSelector`, `.affinity`, `.tolerations` | empty | Scheduling |
| `starrocksOperator.watchNamespace` | `""` (all namespaces) | Restrict the operator to one namespace. Only one namespace can be given. With this set, namespaced Role and RoleBinding are created instead of cluster-wide ones. |
| `starrocksOperator.denyList` | `""` | Comma-separated namespaces the operator must not reconcile. Wins over `watchNamespace`. |
| `starrocksOperator.feSslMode` | `PREFERRED` | See [Security](09-security.md#tls-between-the-operator-and-fe) |
| `starrocksOperator.env` | `[]` | Extra environment variables. `KUBE_STARROCKS_UNSUPPORTED_ENVS` lists variables that must not be passed to StarRocks containers. |
| `starrocksOperator.log` | iso8601 time, console encoder | Log flags |
| `starrocksOperator.dnsDomainSuffix` | `""` (`cluster.local`) | Set if your cluster uses a different DNS suffix. Needed for the FE proxy. |
| `starrocksOperator.volumeNameWithHash` | `true` | Same as the flag above |
| `starrocksOperator.labels`, `.annotations`, `.namespaceOverride` | empty | Metadata |

The full file with comments is at [`upstream/starrocks-kubernetes-operator/helm-charts/charts/kube-starrocks/charts/operator/values.yaml`](../upstream/starrocks-kubernetes-operator/helm-charts/charts/kube-starrocks/charts/operator/values.yaml).

## Scoping the operator

By default one operator manages `StarRocksCluster` objects in every namespace.

- **One operator, many clusters.** Install the operator once, then create clusters in any namespace. This is the simplest setup.
- **One operator per namespace.** Set `watchNamespace` on each operator release. Required if you install more than one `kube-starrocks` umbrella release, because each one brings its own operator.
- **Exclusions.** Use `denyList` to keep an operator out of specific namespaces while it watches the rest.

See [`deploy_multiple_clusters_howto.md`](../upstream/starrocks-kubernetes-operator/doc/deploy_multiple_clusters_howto.md).

## Installing with Argo CD or other GitOps tools

- Argo CD renders Helm with `helm template` and applies the output. Chart hooks that should run only on install, such as the root password job, will run on every sync unless you set `initPassword.isInstall: false` after the first install. See [Security](09-security.md#root-password).
- The CRD is large. Use server-side apply or `Replace=true` sync options if you hit the annotation size limit.
- AWS Data on EKS installs the operator through an Argo CD Application. See [`upstream/data-on-eks/infra/terraform/argocd-applications/starrocks-operator.yaml`](../upstream/data-on-eks/infra/terraform/argocd-applications/starrocks-operator.yaml).

## Restricted or air-gapped clusters

1. Mirror `starrocks/operator`, `starrocks/fe-ubuntu`, `starrocks/be-ubuntu` and `starrocks/cn-ubuntu` to your registry at pinned tags.
2. Download the chart archive or manifests from the release page and host them internally.
3. Override `starrocksOperator.image.repository` and the component `image.repository` values, and set `imagePullSecrets` where needed.

## Upgrade the operator

Manifest path:

```bash
kubectl replace -f starrocks.com_starrocksclusters.yaml   # CRD first
kubectl apply -f operator.yaml
```

Helm path:

```bash
helm repo update starrocks
helm upgrade starrocks-operator starrocks/operator -n starrocks -f operator-values.yaml
```

Helm does not upgrade CRDs that already exist. Apply the new CRD manifest by hand before upgrading the chart. See [Upgrades and day-2 operations](13-upgrades-and-day-2.md#upgrade-the-operator-and-crds).

Restarting or upgrading the operator does not restart FE, BE or CN pods by itself.

## Uninstall

```bash
# Helm
helm uninstall starrocks-operator -n starrocks

# Manifests
kubectl delete -f https://raw.githubusercontent.com/StarRocks/starrocks-kubernetes-operator/main/deploy/operator.yaml
```

Delete `StarRocksCluster` and `StarRocksWarehouse` objects first, while the operator is still running, so it can clean up what it created. Deleting a CRD deletes every object of that kind.

## Upstream sources

- [`deploy_starrocks_with_operator_howto.md`](../upstream/starrocks-kubernetes-operator/doc/deploy_starrocks_with_operator_howto.md)
- [`deploy_starrocks_with_helm_howto.md`](../upstream/starrocks-kubernetes-operator/doc/deploy_starrocks_with_helm_howto.md)
- [`add_helm_repo_howto.md`](../upstream/starrocks-kubernetes-operator/doc/add_helm_repo_howto.md)
- [`deploy/operator.yaml`](../upstream/starrocks-kubernetes-operator/deploy/operator.yaml)
- [`build_your_own_container_image_howto.md`](../upstream/starrocks-kubernetes-operator/doc/build_your_own_container_image_howto.md)
- StarRocks docs: [`sr_operator.md`](../upstream/starrocks/docs/en/deployment/sr_operator.md), [`helm.md`](../upstream/starrocks/docs/en/deployment/helm.md)
