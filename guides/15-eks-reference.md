# 15. EKS reference

What the AWS Data on EKS project deploys for StarRocks, and how to reuse the pieces on an EKS cluster you already have.

Source: [awslabs/data-on-eks](https://github.com/awslabs/data-on-eks), stack `data-stacks/starrocks-on-eks`. The documentation and YAML manifests are copied under [`upstream/data-on-eks/`](../upstream/data-on-eks/). The Terraform, scripts and benchmark jobs are not copied. This guide describes what they do.

## What the stack builds

Running its `deploy.sh` creates a new VPC and EKS cluster and installs everything below. Upstream quotes 15 to 20 minutes.

| Piece | Details |
|---|---|
| StarRocks operator | Version 1.11.3, installed by an Argo CD Application from the `operator` Helm chart, in namespace `starrocks` |
| S3 bucket | For shared-data storage. Public access blocked, AES256 encryption. |
| IAM | A policy on that bucket (`s3:Get*`, `s3:List*`, `s3:*Object*`, plus `s3:ListAllMyBuckets` and `s3:GetBucketLocation`), attached through **EKS Pod Identity** to the ServiceAccount `starrocks-sa` |
| StorageClass | `gp3-starrocks`: EBS gp3, 6000 IOPS, 250 MB/s, xfs, encrypted, `WaitForFirstConsumer`, expandable |
| KEDA | Operator plus a `ScaledObject` for the shared-data CNs |
| Monitoring | Three PodMonitors (FE, BE, CN) and a Grafana dashboard |
| Karpenter NodePools | Reused from the base platform: general-purpose for FE, memory-optimized Graviton for BE and CN, compute-optimized Graviton available |

Stack options live in `terraform/data-stack.tfvars`: `enable_starrocks = true`, with other platform components off by default.

## The two example clusters

| | Shared-data | Shared-nothing |
|---|---|---|
| Manifest | [`starrocks-shared-data.yaml`](../upstream/data-on-eks/data-stacks/starrocks-on-eks/examples/starrocks-shared-data.yaml) | [`starrocks-shared-nothing.yaml`](../upstream/data-on-eks/data-stacks/starrocks-on-eks/examples/starrocks-shared-nothing.yaml) |
| FE | 3 pods, 4 to 8 CPU, 16 to 32 Gi, on `m6g.2xlarge` class nodes | Same |
| Compute | 3 CN on `r8gd.8xlarge` (32 vCPU, 256 GiB, 1.9 TB NVMe). Requests 28 CPU and 220 Gi. | 3 BE on `r8g.8xlarge` with 500 Gi `gp3-starrocks` PVCs |
| StarRocks image | `3.5-latest` | `3.5-latest` |
| FE volumes | `fe-meta` 100 Gi and `fe-log` 10 Gi on `gp3` | Same |
| FE service | Internal Network Load Balancer | `ClusterIP` |

Both set required pod anti-affinity on FE so the three FEs land on three nodes.

### Shared-data settings worth copying

`fe.conf`:

```
run_mode = shared_data
cloud_native_meta_port = 6090
query_timeout = 3600
max_connection = 4096
min_graceful_exit_time_second = 25
aws_s3_path = s3://<bucket>
aws_s3_region = <region>
aws_s3_use_aws_sdk_default_behavior = true
aws_s3_use_instance_profile = true
enable_load_volume_from_conf = true
```

with the FE heap raised to `-Xmx16g` and `-XX:MaxGCPauseMillis=200`.

`cn.conf`:

```
be_port = 9060
webserver_port = 8040
heartbeat_service_port = 9050
brpc_port = 8060
storage_root_path = /mnt/k8s-disks
```

Node selection:

```yaml
nodeSelector:
  NodeGroupType: SparkGravitonMemoryOptimized
  karpenter.sh/capacity-type: on-demand
  karpenter.k8s.aws/instance-family: r8gd
```

FE service:

```yaml
service:
  type: LoadBalancer
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internal"
    service.beta.kubernetes.io/aws-load-balancer-type: "external"
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
```

### Things to notice in that manifest

- **The CN cache path has no volume.** `storage_root_path = /mnt/k8s-disks` is set, and the comments say the path is an NVMe RAID0 array prepared by Karpenter's instance-store policy, but the `StarRocksCluster` declares no `storageVolumes` for CN. As written, the cache lives in the container's writable layer, which sits on the node's ephemeral storage. If you want the mount to be explicit, declare a `hostPath` or `emptyDir` volume at that path. See [Storage](06-storage.md#cn-cache-disks).
- **`serviceAccount: starrocks-sa` is set on CN and at the deprecated top level, not on FE.** FE also needs S3 access in shared-data mode. If your FE cannot reach the bucket, set `serviceAccount` under `starRocksFeSpec` too.
- **`replicas: 3` is fixed on CN** for benchmark repeatability, while the stack also installs a KEDA ScaledObject. To let KEDA scale, remove `replicas`.
- **Images use a moving tag.** Pin a version.
- **The root password is empty.** The docs connect as `root` with no password.

## CN autoscaling with KEDA

The stack scales CN on query activity with scale to zero. Settings and trade-offs are in [Scaling and autoscaling](07-scaling-and-autoscaling.md#autoscaling-cn-with-keda). Upstream's own estimates: scale to zero saves on the order of $1,400 per month per idle CN instance of that size, and the first reads after scale-up come from S3 at roughly 10 to 50 ms each until the cache refills.

Manifest: [`cn-keda-scaledobject.yaml`](../upstream/data-on-eks/infra/terraform/manifests/starrocks/cn-keda-scaledobject.yaml). Replace `${starrocks_namespace}` and `${prometheus_url}` before applying.

## Reusing it on an existing EKS cluster

You do not need the Terraform. Apply the pieces yourself.

### 1. Operator

Install with Helm or manifests as in [Install the operator](02-install-operator.md). The stack's Helm values are small:

```yaml
global:
  rbac:
    create: true
    serviceAccount:
      name: starrocks
timeZone: UTC
starrocksOperator:
  enabled: true
  image: {repository: starrocks/operator, tag: <version>}
  resources:
    requests: {cpu: 100m, memory: 128Mi}
    limits:   {cpu: 500m, memory: 512Mi}
```

### 2. IAM for the pods

Pick one mechanism.

**EKS Pod Identity** (what the stack uses):

```bash
aws eks create-pod-identity-association \
  --cluster-name <cluster> \
  --namespace starrocks \
  --service-account starrocks-sa \
  --role-arn arn:aws:iam::<account>:role/<role>
```

The role's trust policy must allow `pods.eks.amazonaws.com`, and the Pod Identity Agent add-on must be installed.

**IRSA:**

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: starrocks-sa
  namespace: starrocks
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::<account>:role/<role>
```

Then set `serviceAccount: starrocks-sa` on FE and CN (and BE if used).

Grant the role what the cluster needs: the shared-data bucket, any data lake buckets, and AWS Glue if you use Glue catalogs. See [Security](09-security.md#cloud-credentials).

### 3. Storage

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3-starrocks
provisioner: ebs.csi.aws.com
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
parameters:
  type: gp3
  iops: "6000"
  throughput: "250"
  encrypted: "true"
  fsType: "xfs"
```

Needs the EBS CSI driver. Use it for FE metadata and BE data. `reclaimPolicy: Delete` removes the EBS volume when the PVC is deleted, so consider `Retain` for FE metadata and BE data.

For CN cache, choose from the options in [Storage](06-storage.md#cn-cache-disks). A default gp3 volume has modest baseline throughput, so provision IOPS and throughput explicitly if you cache on EBS.

### 4. Nodes

- FE: general-purpose instances, on-demand, spread across at least three nodes. Spreading across zones protects against a zone failure. EBS volumes are zonal, so an FE pod stays in the zone of its volume.
- BE: memory-optimized, on-demand. EBS volumes pin each BE to a zone.
- CN: memory-optimized. One instance type per cluster, since CN hardware must be uniform. Local NVMe variants (the `d` families) give a fast cache. Spot is possible for CN because it holds no data, at the cost of failed in-flight queries and lost cache on interruption.
- Stop Karpenter from consolidating FE and BE nodes during business hours. Use the `karpenter.sh/do-not-disrupt` pod annotation or disruption budgets.

### 5. Network

- Use an internal load balancer for the FE service, or keep it `ClusterIP` and connect through a private path.
- In private subnets add VPC endpoints for S3, STS, Glue, ECR and, for Pod Identity, the EKS auth endpoint.
- Security groups must allow pod-to-pod traffic on the StarRocks ports. See [Networking and access](08-networking-and-access.md#traffic-inside-the-cluster).

### 6. Monitoring

Apply the PodMonitors, or use the chart's ServiceMonitor. See [Observability](12-observability.md).

### 7. The cluster

Start from the Data on EKS shared-data manifest or from [`examples/shared-data-s3.yaml`](examples/shared-data-s3.yaml), and adjust node selectors, ServiceAccount, bucket and sizes.

## Sizing reference from the benchmark

The stack's benchmark pages describe a 1 TB TPC-DS run on the shapes above, comparing shared-data and shared-nothing. Treat them as one data point on specific hardware, not a prediction for your data.

- [`tpcds-benchmark.md`](../upstream/data-on-eks/website/docs/datastacks/databases/starrocks-on-eks/tpcds-benchmark.md)
- [`starrocks-benchmark.md`](../upstream/data-on-eks/website/docs/benchmarks/starrocks-benchmark.md)

## Troubleshooting on EKS

| Symptom | Check |
|---|---|
| Pods stuck `Pending` | `kubectl describe pod`, Karpenter logs, `kubectl get nodeclaims`. Common causes: provisioning delay of a few minutes, instance type not available in the zone, node selector asking for a family the NodePool cannot provide. |
| FE cannot reach S3 | Is the ServiceAccount set on FE? Does it have the role? Look for S3 errors in the FE log. |
| PVC stuck `Pending` | EBS CSI driver installed? StorageClass exists? `WaitForFirstConsumer` means it binds only when the pod schedules. |
| Pod cannot reschedule after a zone problem | Its EBS volume is in the failed zone |
| KEDA not scaling | `kubectl describe scaledobject`, the HPA KEDA created, KEDA operator logs, and whether KEDA can reach Prometheus |
| Load balancer not created | AWS Load Balancer Controller installed? Subnets tagged for internal load balancers? |

## Upstream sources

- [`index.md`](../upstream/data-on-eks/website/docs/datastacks/databases/starrocks-on-eks/index.md)
- [`infra.md`](../upstream/data-on-eks/website/docs/datastacks/databases/starrocks-on-eks/infra.md)
- [`storageclass.yaml`](../upstream/data-on-eks/infra/terraform/manifests/starrocks/storageclass.yaml)
- [`pod-monitors.yaml`](../upstream/data-on-eks/infra/terraform/manifests/starrocks/pod-monitors.yaml)
- [`helm-values/starrocks-operator.yaml`](../upstream/data-on-eks/infra/terraform/helm-values/starrocks-operator.yaml)
- [`argocd-applications/starrocks-operator.yaml`](../upstream/data-on-eks/infra/terraform/argocd-applications/starrocks-operator.yaml)
