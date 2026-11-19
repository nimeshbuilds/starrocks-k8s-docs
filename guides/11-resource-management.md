# 11. Resource management

How to keep one workload from starving another inside a cluster: resource groups, query queues, big-query limits and spill to disk.

These are StarRocks features, set in SQL. They work the same on Kubernetes as anywhere else, with one difference: limits are per BE or CN node, so they scale as pods are added.

## The tools

| Tool | What it controls | Scope |
|---|---|---|
| Resource groups | CPU share, memory share, concurrency, big-query limits | Per group of queries, matched by classifier |
| Query queues | Admission. Hold queries when the cluster is saturated instead of failing them. | Cluster, or per resource group |
| Spill to disk | Lets large joins, aggregations and sorts overflow to disk instead of running out of memory | Session, global or resource group |
| Session limits | `query_timeout`, `query_mem_limit` and similar | Session or user |
| Warehouses | Physically separate CN pools | Enterprise edition. See [Scaling](07-scaling-and-autoscaling.md#warehouses). |

## Resource groups

Resource groups are enabled by default from v3.1.0.

### Create a group

```sql
CREATE RESOURCE GROUP <group_name>
TO (
    user='string',
    role='string',
    query_type in ('select'),
    source_ip='cidr'
)   -- one classifier. Separate several with commas.
WITH (
    "cpu_weight" = "INT",          -- or exclusive_cpu_cores
    "mem_limit" = "m%",
    "concurrency_limit" = "INT"
);
```

### Resource parameters

| Parameter | Meaning | Default |
|---|---|---|
| `cpu_weight` | CPU scheduling weight on each node. Range (0, average cores per BE]. A share, enforced only under contention. | 0 |
| `cpu_weight_percent` | The same as a percentage of the node's cores. From v4.1. | 0 |
| `exclusive_cpu_cores` | Cores reserved for this group. Hard isolation. Range (0, minimum cores per BE minus 1]. | 0 |
| `exclusive_cpu_percent` | The same as a percentage | 0 |
| `mem_limit` | Share of node query memory this group may use. Required. | |
| `mem_pool` | Groups with the same pool name share one memory limit. From v4.0. | |
| `concurrency_limit` | Maximum concurrent queries in the group | 0 (no limit) |
| `big_query_cpu_second_limit` | CPU seconds a query may use on each node before it is terminated | 0 (off) |
| `big_query_scan_rows_limit` | Rows a query may scan on each node before it is terminated | 0 (off) |
| `big_query_mem_limit` | Bytes of memory a query may use on each node before it is terminated | 0 (off) |
| `spill_mem_limit_threshold` | Fraction of the group's memory at which queries start spilling | 1.0 |

Only one of `cpu_weight`, `cpu_weight_percent`, `exclusive_cpu_cores` and `exclusive_cpu_percent` can be greater than 0 for a group.

- **Weights** divide CPU proportionally when nodes are busy. Groups with weights 2, 6 and 8 get 12.5%, 37.5% and 50% of a fully loaded node. Idle CPU is free for anyone.
- **Exclusive cores** are taken out of the shared pool. The total across all exclusive groups cannot exceed the smallest node's cores minus one. By default, shared groups may borrow idle exclusive cores. Turn that off with the BE setting `enable_resource_group_cpu_borrowing = false`.

Because limits are per node, they assume nodes are the same size. That is already a requirement for CNs in a shared-data cluster.

### Classifiers

A classifier decides which queries land in a group.

| Field | Matches |
|---|---|
| `user` | User name |
| `role` | Role of the user |
| `query_type` | `select` or `insert` |
| `source_ip` | Client CIDR block |
| `db` | Database the query touches. Several names separated by commas. |
| `plan_cpu_cost_range` | Estimated CPU cost range `(low, high]` |

When several classifiers match, the most specific wins. Each matching field adds to a score: `db` adds 10, `user` and `role` add 1 each, and `query_type` and `source_ip` add 1 plus a fraction for specificity.

Queries that match nothing run in `default_wg`. Materialized view refreshes run in `default_mv_wg` unless the view names another group. Both system groups can be altered but not dropped.

### Manage groups

```sql
SHOW RESOURCE GROUPS ALL;
SHOW RESOURCE GROUP rg_name;

ALTER RESOURCE GROUP rg_name WITH ('cpu_weight' = '8', 'mem_limit' = '30%');
ALTER RESOURCE GROUP rg_name ADD (user='svc_reports', query_type in ('select'));
ALTER RESOURCE GROUP rg_name DROP (<classifier_id>, ...);
ALTER RESOURCE GROUP rg_name DROP ALL;
DROP RESOURCE GROUP rg_name;

-- pin the current session to a group
SET resource_group = 'rg_name';

-- see which group a query would use
EXPLAIN VERBOSE SELECT ...;
```

The group a finished query ran in is recorded in the `ResourceGroup` column of `fe.audit.log`.

### A pattern for three workloads

Suppose one cluster serves interactive analysts, scheduled jobs, and automated or agent-driven queries.

```sql
-- Interactive: generous share, moderate concurrency
CREATE RESOURCE GROUP rg_interactive
TO (role='analyst', query_type in ('select'))
WITH (
    'cpu_weight' = '8',
    'mem_limit' = '50%',
    'concurrency_limit' = '30'
);

-- Scheduled jobs: steady share, protected from the others
CREATE RESOURCE GROUP rg_scheduled
TO (user='svc_scheduler')
WITH (
    'cpu_weight' = '6',
    'mem_limit' = '40%',
    'concurrency_limit' = '50'
);

-- Automated callers: small share, hard caps on runaway queries
CREATE RESOURCE GROUP rg_automation
TO (user='svc_agent')
WITH (
    'cpu_weight' = '2',
    'mem_limit' = '20%',
    'concurrency_limit' = '10',
    'big_query_cpu_second_limit' = '600',
    'big_query_scan_rows_limit' = '50000000000',
    'big_query_mem_limit' = '34359738368'
);
```

Treat the numbers as placeholders. Set them from your node sizes and from the `PlanCpuCost`, scan rows and memory figures of real queries in the audit log. A full script is in [`examples/resource-groups.sql`](examples/resource-groups.sql).

Notes:

- `mem_limit` is a ceiling on the group, not a reservation. Check the upstream page for how limits across groups interact in your version.
- The big-query limits are counted per node, so the cluster-wide ceiling grows with the number of CNs.
- Give each workload its own database user or role. Classifiers cannot tell workloads apart otherwise.

## Big queries

A resource group with `big_query_*` limits terminates queries that cross them. This is the main guard against a query with no partition filter on a very large table.

```sql
-- what is running now
SHOW PROC '/current_queries';
SHOW PROC '/current_queries/<QueryId>/hosts';

-- stop one. The argument is the connection ID.
KILL QUERY <ConnectionId>;
```

From v3.0 there is also a big-query log, `fe.big_query.log` in the FE log directory:

```sql
SET GLOBAL enable_big_query_log = true;
SET GLOBAL big_query_log_cpu_second_threshold = 600;
```

Upstream page: [`monitor_manage_big_queries.md`](../upstream/starrocks/docs/en/administration/management/monitor_manage_big_queries.md).

## Query queues

Queues hold incoming queries when a threshold is reached, instead of letting every query in.

```sql
SET GLOBAL enable_query_queue_select = true;
SET GLOBAL enable_query_queue_statistic = true;
SET GLOBAL enable_query_queue_load = true;
```

Thresholds, checked per node:

| Variable | Default | Meaning |
|---|---|---|
| `query_queue_concurrency_limit` | 0 | Concurrent queries on a node |
| `query_queue_mem_used_pct_limit` | 0 | Memory usage percentage on a node |
| `query_queue_cpu_used_permille_limit` | 0 | CPU usage per mille on a node. Not used for triggering under Query Queue v2. |
| `query_queue_max_queued_queries` | 1024 | Queue length. Beyond it, new queries are rejected. |
| `query_queue_pending_timeout_second` | 300 | How long a query may wait before it is rejected |

Zero means no limit.

Version notes:

- **Query Queue v2** is a slot-based scheduler, controlled by the FE setting `enable_query_queue_v2`. It is the default from v4.1. Changing it needs an FE restart. It is tuned with `query_queue_v2_concurrency_level` and `query_queue_slots_estimator_strategy`.
- **Resource group-level queues** (`enable_group_level_query_queue`) belong to Query Queue v1. Read the upstream page for how `concurrency_limit` behaves once v2 is on.

Upstream page: [`query_queues.md`](../upstream/starrocks/docs/en/administration/management/resource_management/query_queues.md).

## Spill to disk

Spilling lets hash joins, aggregations and sorts write intermediate results to disk when memory runs short. It is off by default.

1. Give the nodes a spill directory in `cn.conf` or `be.conf`:

   ```
   spill_local_storage_dir = /opt/starrocks/cn/spill
   ```

   Several directories can be separated with `;`. Back it with a volume. See [Storage](06-storage.md).

2. Turn it on:

   ```sql
   SET GLOBAL enable_spill = true;
   SET GLOBAL spill_mode = 'auto';      -- or 'force'
   ```

| Variable | Default | Meaning |
|---|---|---|
| `enable_spill` | `false` | Enable spilling |
| `spill_mode` | `auto` | `auto` spills when a memory threshold is reached. `force` always spills. |

With resource groups, a query starts spilling when the group's memory use passes `mem_limit * spill_mem_limit_threshold`, or when the query passes 80% of `query_mem_limit`.

Spilling to object storage is also possible, which suits CNs with little local disk:

```sql
SET enable_spill_to_remote_storage = true;
SET spill_storage_volume = '<storage_volume_name>';
```

The storage volume must exist, or remote spill stays off.

Limits to know: the spill directory is shared by all queries on a node with no per-query size cap, and not every out-of-memory case can be avoided by spilling.

Upstream page: [`spill_to_disk.md`](../upstream/starrocks/docs/en/administration/management/resource_management/spill_to_disk.md).

## Memory

- FE heap is set with `-Xmx` in `JAVA_OPTS`. Keep it below the pod memory limit with room for off-heap use.
- BE and CN size their memory from the container limit. Keep `requests` equal to `limits` so the scheduler does not overcommit the node.
- `query_mem_limit` caps one query. Resource group `mem_limit` caps a group.

Upstream pages: [`Memory_management.md`](../upstream/starrocks/docs/en/administration/management/resource_management/Memory_management.md), [`Query_management.md`](../upstream/starrocks/docs/en/administration/management/resource_management/Query_management.md).

## Isolation beyond resource groups

Resource groups share nodes. If one workload must never affect another:

- Run a second cluster. One operator can manage several clusters, and external catalogs can point at the same lake. Each cluster keeps its own cache and metadata cache.
- Use warehouses if you run the enterprise edition.

## Upstream sources

- [`resource_group.md`](../upstream/starrocks/docs/en/administration/management/resource_management/resource_group.md)
- [`query_queues.md`](../upstream/starrocks/docs/en/administration/management/resource_management/query_queues.md)
- [`spill_to_disk.md`](../upstream/starrocks/docs/en/administration/management/resource_management/spill_to_disk.md)
- [`monitor_manage_big_queries.md`](../upstream/starrocks/docs/en/administration/management/monitor_manage_big_queries.md)
- [`resource_management/`](../upstream/starrocks/docs/en/administration/management/resource_management/)
