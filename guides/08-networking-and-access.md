# 8. Networking and access

How clients reach StarRocks, and how the pieces reach each other.

## Services the operator creates

For a cluster named `sr`:

| Service | Type | Ports | Use |
|---|---|---|---|
| `sr-fe-service` | Configurable, default `ClusterIP` | 8030, 9020, 9030, 9010 | **The client entry point.** MySQL on 9030, HTTP on 8030. |
| `sr-fe-search` | Headless | 9030 | FE discovery. Internal. |
| `sr-be-service` | Configurable, default `ClusterIP` | 9060, 8040, 9050, 8060 | BE access |
| `sr-be-search` | Headless | 9050 | BE discovery. Internal. |
| `sr-cn-service` | Configurable, default `ClusterIP` | CN ports | CN access |
| `sr-cn-search` | Headless | | CN discovery. Internal. |
| FE proxy service | Configurable | 8080 | Stream Load from outside the cluster network |

Connect clients to the `-service` Services only. The `-search` Services exist so pods can find each other by stable DNS name.

Annotations and labels under `spec.<component>.service` are applied to the client-facing Service, not the headless one.

## Connecting

### From inside the cluster

```bash
mysql -h sr-fe-service.starrocks.svc.cluster.local -P 9030 -u root -p
```

Any MySQL-protocol client or driver works. BI tools connect the same way, to port 9030.

### Port-forward, for administration

```bash
kubectl -n starrocks port-forward svc/sr-fe-service 9030:9030
mysql -h 127.0.0.1 -P 9030 -u root -p
```

### LoadBalancer

```yaml
starRocksFeSpec:
  service:
    type: LoadBalancer
    annotations:
      # example: internal AWS Network Load Balancer with IP targets
      service.beta.kubernetes.io/aws-load-balancer-scheme: "internal"
      service.beta.kubernetes.io/aws-load-balancer-type: "external"
      service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
    loadBalancerSourceRanges:
      - 10.0.0.0/8
```

```bash
kubectl -n starrocks get svc sr-fe-service \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

The AWS annotations above come from the Data on EKS shared-data example and need the AWS Load Balancer Controller. Use the annotations for your own cloud and controller.

A LoadBalancer on the FE service exposes all four FE ports. Restrict it with `loadBalancerSourceRanges`, a network policy, or by limiting `service.ports`.

### NodePort

```yaml
starRocksFeSpec:
  service:
    type: NodePort
    ports:
      - name: query          # FE port names: http, query, rpc, edit-log
        port: 9030
        containerPort: 9030
        nodePort: 32755      # 30000 to 32767
```

Identify a port by `name` or `containerPort`. If both are given, `containerPort` wins.

### Other service fields

| Field | Use |
|---|---|
| `loadBalancerIP` | Static address, where the platform supports it |
| `externalTrafficPolicy` | `Local` keeps the client source IP. `Cluster` balances more evenly. Applies to NodePort and LoadBalancer. |

## Load balancing and FE roles

Every FE accepts client connections. A Service in front of all FEs spreads connections across them. Followers forward writes and metadata changes to the leader internally. You do not need to route to the leader yourself.

MySQL connections are long-lived, so balancing is per connection, not per query. A client that opens one connection and keeps it stays on one FE.

## Stream Load from outside the cluster: FE proxy

Stream Load is an HTTP API. The client sends the request to FE, and FE answers with an HTTP 307 redirect to a BE or CN pod. From outside the cluster network that redirect points at a private pod address the client cannot reach.

The FE proxy is an nginx reverse proxy that follows the redirect on the client's behalf.

```yaml
spec:
  starRocksFeProxySpec:
    replicas: 1
    requests: {cpu: 1, memory: 2Gi}
    limits:   {cpu: 1, memory: 2Gi}
    service:
      type: NodePort            # or LoadBalancer
      ports:
        - name: http-port
          containerPort: 8080
          port: 8080
          nodePort: 30180
    resolver: "kube-dns.kube-system.svc.cluster.local"
```

Then send Stream Load requests to the proxy on port 8080 instead of FE on 8030.

- `resolver` is the DNS server nginx uses. The default is `kube-dns.kube-system.svc.cluster.local`. Clusters that name their DNS Service differently must change it.
- If the cluster's DNS suffix is not `cluster.local`, set the operator's `dnsDomainSuffix` so it writes the right names into the nginx config.
- The proxy handles HTTP only. Tools that read from BE over Thrift, such as the Spark connector's read path, cannot go through it. Upstream's workaround for reading from outside the cluster is `INSERT INTO FILES` to export, then read the files.
- Clients inside the cluster do not need the proxy.

With Helm, set `starrocksFeProxySpec.enabled: true` and the same fields.

## Traffic inside the cluster

| From | To | Port | Why |
|---|---|---|---|
| Clients | FE | 9030 | SQL |
| Clients, loaders | FE | 8030 | HTTP API, Stream Load |
| FE | FE | 9010, 9020 | Metadata replication, RPC |
| FE | BE / CN | 9050, 9060, 8060 | Heartbeat, task dispatch, query fragments |
| BE / CN | BE / CN | 8060 | Data exchange during queries |
| BE / CN | FE | 9020 | Reports |
| FE | CN | 9070 | Shared-data agent |
| CN | FE | 6090 | Shared-data metadata |
| Operator | FE | 9030 | Maintenance SQL such as `SHOW COMPUTE NODES` |
| Prometheus | FE, BE / CN | 8030, 8040 | `/metrics` |

This table is derived from the port definitions in the upstream docs. Confirm it against observed traffic before you enforce strict policies. Also allow DNS, the Kubernetes API for the operator, your object store, and your metastore or AWS Glue.

## Outbound access the pods need

| Destination | Who needs it |
|---|---|
| Object storage (for example S3) | FE and CN in shared-data mode. FE, BE and CN for external catalogs. |
| Metastore: Hive Metastore, AWS Glue, an Iceberg REST catalog | FE |
| Cloud credential endpoints (STS, pod identity agent) | Any pod using IAM roles |
| Image registry | Nodes |

In private networks, add VPC endpoints or proxies for these. A cluster that starts but cannot create tables or list databases is usually missing one of them.

## Service mesh

StarRocks nodes talk to each other by pod DNS name over several non-HTTP protocols. If you run a sidecar mesh:

- Treat 9010, 9020, 9050, 9060 and 8060 as opaque TCP.
- Make sure the sidecar is ready before the StarRocks container starts, or FE registration can fail at startup.
- Check that graceful shutdown still has time to finish. See [Configuration](05-configuration.md#graceful-shutdown).

Test in a non-production cluster first. Upstream does not document a mesh setup.

## Upstream sources

- [`deploy_starrocks_with_operator_howto.md`](../upstream/starrocks-kubernetes-operator/doc/deploy_starrocks_with_operator_howto.md), section 3.1
- [`load_data_using_stream_load_howto.md`](../upstream/starrocks-kubernetes-operator/doc/load_data_using_stream_load_howto.md)
- [`deploy_a_starrocks_cluster_with_fe_proxy.yaml`](../upstream/starrocks-kubernetes-operator/examples/starrocks/deploy_a_starrocks_cluster_with_fe_proxy.yaml)
- [`environment_configurations.md`](../upstream/starrocks/docs/en/deployment/preparation/environment_configurations.md)
- [`Load_balance.md`](../upstream/starrocks/docs/en/administration/management/resource_management/Load_balance.md)
- [`StreamLoad.md`](../upstream/starrocks/docs/en/loading/StreamLoad.md)
