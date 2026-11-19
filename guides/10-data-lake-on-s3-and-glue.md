# 10. Data lake on S3 and Glue

How to query tables that already exist in an S3 data lake, registered in the AWS Glue Data Catalog, without loading them into StarRocks.

StarRocks reaches a lake through an **external catalog**. The catalog holds connection settings only. Data and metadata stay in S3 and Glue.

## Pick the catalog type

| Tables in Glue are | Use | Upstream page |
|---|---|---|
| Hive-style: Parquet, ORC or text files under partition directories | Hive catalog | [`hive_catalog.md`](../upstream/starrocks/docs/en/data_source/catalog/hive_catalog.md) |
| Apache Iceberg | Iceberg catalog | [`iceberg/iceberg.md`](../upstream/starrocks/docs/en/data_source/catalog/iceberg/iceberg.md) |
| Delta Lake | Delta Lake catalog | [`deltalake_catalog.md`](../upstream/starrocks/docs/en/data_source/catalog/deltalake_catalog.md) |
| Apache Hudi | Hudi catalog | [`hudi_catalog.md`](../upstream/starrocks/docs/en/data_source/catalog/hudi_catalog.md) |
| A mix in one metastore | Unified catalog | [`unified_catalog.md`](../upstream/starrocks/docs/en/data_source/catalog/unified_catalog.md) |

Hive tables support Parquet, ORC, Textfile, Avro, RCFile and SequenceFile. Parquet compression codecs SNAPPY, LZ4, ZSTD, GZIP and uncompressed are supported.

## Prerequisites

1. A running cluster. Shared-data with CNs is the natural fit, since compute is stateless.
2. An IAM role with read access to the Glue catalog and the S3 buckets, bound to the ServiceAccount used by **FE and CN**. See [Security](09-security.md#cloud-credentials).
3. Network reachability from the pods to Glue, S3 and STS. In private subnets, add VPC endpoints.

FE talks to Glue and lists files in S3 during planning. CN (or BE) reads the data files.

## Create a Hive catalog on Glue

```sql
CREATE EXTERNAL CATALOG hive_glue
PROPERTIES
(
    "type" = "hive",
    "hive.metastore.type" = "glue",
    "aws.glue.use_instance_profile" = "true",
    "aws.glue.region" = "us-east-1",
    "aws.s3.use_instance_profile" = "true",
    "aws.s3.region" = "us-east-1"
);
```

`use_instance_profile = true` means "use the credentials the pod already has", which is your ServiceAccount's IAM role.

### Glue parameters

| Property | Required | Meaning |
|---|---|---|
| `hive.metastore.type` | Yes | `glue` |
| `aws.glue.use_instance_profile` | Yes | Use instance-profile or assumed-role authentication. Default `false`. |
| `aws.glue.iam_role_arn` | No | Role to assume for Glue |
| `aws.glue.region` | Yes | Region of the Glue Data Catalog |
| `aws.glue.access_key`, `aws.glue.secret_key` | No | IAM user credentials. Avoid. |
| `hive.metastore.glue.catalogid` | No | Glue catalog ID. Needed for cross-account catalogs. |
| `aws.glue.resource_share_type` | No | Controls which shared databases `SHOW DATABASES` lists |

### S3 parameters

| Property | Required | Meaning |
|---|---|---|
| `aws.s3.use_instance_profile` | Yes | Use instance-profile or assumed-role authentication. Default `false`. |
| `aws.s3.iam_role_arn` | No | Role to assume for S3 |
| `aws.s3.region` | Yes | Bucket region |
| `aws.s3.access_key`, `aws.s3.secret_key` | No | IAM user credentials. Avoid. |

### Three authentication patterns

```sql
-- 1. Pod's own role
"aws.glue.use_instance_profile" = "true",
"aws.s3.use_instance_profile" = "true"

-- 2. Assume another role, for example cross-account
"aws.glue.use_instance_profile" = "true",
"aws.glue.iam_role_arn" = "arn:aws:iam::<account>:role/<role>",
"aws.s3.use_instance_profile" = "true",
"aws.s3.iam_role_arn" = "arn:aws:iam::<account>:role/<role>"

-- 3. Static keys
"aws.glue.use_instance_profile" = "false",
"aws.glue.access_key" = "<key>", "aws.glue.secret_key" = "<secret>",
"aws.s3.use_instance_profile" = "false",
"aws.s3.access_key" = "<key>", "aws.s3.secret_key" = "<secret>"
```

## Create an Iceberg catalog on Glue

```sql
CREATE EXTERNAL CATALOG iceberg_glue
PROPERTIES
(
    "type" = "iceberg",
    "iceberg.catalog.type" = "glue",
    "aws.glue.use_instance_profile" = "true",
    "aws.glue.region" = "us-east-1",
    "aws.s3.use_instance_profile" = "true",
    "aws.s3.region" = "us-east-1"
);
```

## Use the catalog

```sql
SHOW CATALOGS;
SHOW DATABASES FROM hive_glue;

SET CATALOG hive_glue;
USE lake_db;
SHOW TABLES;

-- or fully qualified, from any catalog
SELECT count(*) FROM hive_glue.lake_db.events WHERE dt = '2026-01-01';
```

Always filter on partition columns. Without a partition filter, StarRocks has to list and plan over every partition.

A full script is in [`examples/glue-catalogs.sql`](examples/glue-catalogs.sql).

## Metadata caching and freshness

StarRocks caches lake metadata so it does not call Glue and list S3 for every query. The price is a delay before new data is visible.

### Hive catalog cache properties

Set these in `PROPERTIES` when you create the catalog.

| Property | Default | Meaning |
|---|---|---|
| `enable_metastore_cache` | `true` | Cache table and partition metadata |
| `enable_remote_file_cache` | `true` | Cache the file listings of tables and partitions |
| `metastore_cache_refresh_interval_sec` | `60` | How often cached table and partition metadata is refreshed in the background. Was `7200` before v3.3.0. |
| `remote_file_cache_refresh_interval_sec` | `60` | How often cached file listings are refreshed |
| `metastore_cache_ttl_sec` | `86400` | When cached table and partition metadata is discarded |
| `remote_file_cache_ttl_sec` | `129600` | When cached file listings are discarded |
| `enable_cache_list_names` | `true` | Cache partition names |
| `remote_file_cache_memory_ratio` | `0.1` | Memory ceiling for the file cache, from v3.5.6 |
| `enable_recursive_listing` | `true` | Read files in subdirectories of table and partition locations |

There is also a background job, controlled by FE parameters, that refreshes metadata for recently used Hive catalogs:

| FE parameter | Default | Meaning |
|---|---|---|
| `enable_background_refresh_connector_metadata` | `true` | Turn the periodic refresh on or off |
| `background_refresh_metadata_interval_millis` | `600000` (10 min) | Interval between refreshes |
| `background_refresh_metadata_time_secs_since_last_access_secs` | `86400` (24 h) | Stop refreshing a catalog that has not been used for this long |

### What this means in practice

- A new file in an existing partition, or a new partition, may not be visible for up to the refresh interval.
- Only metadata that has been queried is cached and refreshed. The first query on a cold partition goes to Glue and S3.
- Schema changes, `INSERT OVERWRITE` into an existing partition, and drop-and-recreate of a table need a manual refresh.

```sql
REFRESH EXTERNAL TABLE hive_glue.lake_db.events;
REFRESH EXTERNAL TABLE hive_glue.lake_db.events PARTITION ('dt=2026-01-01');
```

`REFRESH EXTERNAL TABLE` refreshes only what is already cached in the FEs.

### Choosing settings

| Need | Setting |
|---|---|
| Lowest planning latency, data arrives in batches | Keep the defaults |
| Jobs that must see the newest files (alerting, incremental processing) | Lower the two `*_refresh_interval_sec` values, or run `REFRESH EXTERNAL TABLE` before the job, or query a window that ends a few minutes in the past |
| Always fresh, cost is acceptable | `"enable_metastore_cache" = "false"` and `"enable_remote_file_cache" = "false"` on a dedicated catalog for those jobs |

You can create two catalogs over the same Glue database with different cache settings, one for interactive use and one for freshness-critical jobs.

### Iceberg cache

| Property | Default | Meaning |
|---|---|---|
| `enable_iceberg_metadata_cache` | `true` | Cache table, partition-name and manifest file metadata |
| `iceberg_table_cache_refresh_interval_sec` | `60` | Background refresh interval for the table cache, from v3.5.7 |
| `iceberg_manifest_cache_with_column_statistics` | `true` | Cache column statistics used for file-level pruning |

Iceberg planning reads manifests, which carry per-file statistics. That makes file pruning cheaper than directory listing on large tables.

## Data cache

The data cache keeps blocks of remote files on the CN or BE, so repeated reads skip S3. It has two parts: a page cache in memory and a block cache on local disk.

### Settings

| Where | Setting | Default | Meaning |
|---|---|---|---|
| `cn.conf` / `be.conf` | `datacache_enable` | `true` | Master switch for both parts |
| `cn.conf` / `be.conf` | `block_cache_enable` | `true` | Disk block cache |
| `cn.conf` / `be.conf` | `disable_storage_page_cache` | `false` | Set `true` to turn off the memory page cache |
| `cn.conf` / `be.conf` | `datacache_mem_size` | | Memory ceiling, absolute or percent |
| `cn.conf` / `be.conf` | `datacache_disk_size` | | Disk ceiling, absolute or percent |
| `cn.conf` / `be.conf` | `enable_datacache_disk_auto_adjust` | `true` | Grow and shrink disk use automatically, up to `datacache_disk_size` if set |
| session / global | `enable_scan_datacache` | `true` | Let queries read from the cache |
| session / global | `populate_datacache_mode`, `enable_datacache_async_populate_mode` | | Control how the cache is filled. Async population is the default from v3.3.0. |

Limits can be changed at runtime:

```sql
UPDATE information_schema.be_configs SET VALUE="10%" WHERE NAME="datacache_mem_size";
UPDATE information_schema.be_configs SET VALUE="500G" WHERE NAME="datacache_disk_size";
```

Runtime changes are lost on restart unless you also put them in the ConfigMap.

For native tables in a shared-data cluster, two more BE and CN settings apply: `starlet_use_star_cache` and `starlet_star_cache_disk_size_percent`. Tables also have `datacache.enable` and `datacache.partition_duration` properties.

### Does the cache help your workload?

- It helps when the same data is read repeatedly: dashboards, scheduled queries over recent partitions, iterative analysis.
- It helps little when most queries scan large amounts of cold data once. Only the blocks a query actually reads are cached, and old blocks are evicted when the disk limit is reached.
- A cache on a slow volume can be slower than S3. Upstream recommends local NVMe. See [Storage](06-storage.md#cn-cache-disks).

### Running without a disk cache

```
# cn.conf
block_cache_enable = false
```

or, in shared-data mode, leave `storage_root_path` empty. You keep the memory page cache and lose nothing in correctness.

### Check whether a query used the cache

Look in the query profile:

| Metric | Meaning |
|---|---|
| `DataCacheReadBytes` | Bytes served from memory and disk cache |
| `DataCacheWriteBytes` | Bytes fetched from remote storage and written into the cache |
| `BytesRead` | Total bytes read from all sources |

A high `DataCacheReadBytes` relative to `BytesRead` means the cache is working.

### Warm the cache

```sql
CACHE SELECT col_a, col_b FROM hive_glue.lake_db.events WHERE dt >= '2026-01-01';
```

`CACHE SELECT` fetches the data into the cache without returning rows. See [`block_cache_warmup.md`](../upstream/starrocks/docs/en/data_source/data_cache/block_cache_warmup.md).

## Statistics

The optimizer plans better with table statistics. For external tables, collect them with `ANALYZE TABLE`. Join order and join strategy on lake tables depend on this. See [`using_starrocks/Cost_based_optimizer.md`](../upstream/starrocks/docs/en/using_starrocks/Cost_based_optimizer.md).

## Materialized views over lake tables

An asynchronous materialized view can be built on external catalog tables. StarRocks stores the result as a native table and can rewrite matching queries to read the view instead of the lake.

```sql
CREATE MATERIALIZED VIEW default_catalog.mv.events_daily
PARTITION BY dt
REFRESH ASYNC EVERY (INTERVAL 1 HOUR)
AS
SELECT dt, event_source, event_name, count(*) AS events
FROM hive_glue.lake_db.events
GROUP BY dt, event_source, event_name;
```

Facts from upstream:

- Views must be created in `default_catalog`.
- Views on external tables refresh on a fixed interval or manually. They are not refreshed automatically when the base table changes.
- For Hive, Iceberg and Paimon catalogs, refresh can be incremental at partition level.
- Queries are rewritten to use the view only while it is consistent with the base table. If the lake table has changed since the last refresh, the query is not rewritten, unless you allow staleness with the view property `mv_rewrite_staleness_second`.
- Rewrite is off by default for views on Hudi and JDBC catalogs. The data lake acceleration page explains how to turn it on.
- Refresh tasks run in the `default_mv_wg` resource group unless you assign another.

Pages:

- [`data_lake_query_acceleration_with_materialized_views.md`](../upstream/starrocks/docs/en/using_starrocks/async_mv/use_cases/data_lake_query_acceleration_with_materialized_views.md)
- [`query_rewrite_with_materialized_views.md`](../upstream/starrocks/docs/en/using_starrocks/async_mv/use_cases/query_rewrite_with_materialized_views.md)
- [`Materialized_view.md`](../upstream/starrocks/docs/en/using_starrocks/async_mv/Materialized_view.md)

## Table layout matters more than engine settings

For large lake tables, what the engine can skip decides the cost of a query.

- Partition on the column almost every query filters by, usually a date.
- Keep files reasonably large. Many small files multiply listing and open costs for every engine.
- Sort data within files on the columns you look up by, so min and max statistics can exclude row groups.
- Prefer a table format with file-level statistics, such as Iceberg, for very large tables.

## Trino compatibility

Queries written for Trino can often run unchanged:

```sql
SET sql_dialect = 'trino';
```

See [`sql-reference/System_variable.md`](../upstream/starrocks/docs/en/sql-reference/System_variable.md) for `sql_dialect`.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `SHOW DATABASES FROM <catalog>` is empty or errors | FE pod has no Glue permission, wrong `aws.glue.region`, or no network path to Glue |
| Databases list but queries fail with access errors | CN or BE pods lack S3 permission. Set `serviceAccount` on CN as well as FE. |
| New data does not appear | Metadata cache. See above. |
| Planning is slow on the first query | Cold metadata cache, many partitions or many small files |
| Cross-account catalog shows nothing | Set `hive.metastore.glue.catalogid` and check the resource share type |

More in [`datalake_faq.md`](../upstream/starrocks/docs/en/data_source/datalake_faq.md) and [`data_cache_troubleshooting.md`](../upstream/starrocks/docs/en/data_source/data_cache/data_cache_troubleshooting.md).

## Upstream sources

- [`catalog_overview.md`](../upstream/starrocks/docs/en/data_source/catalog/catalog_overview.md)
- [`hive_catalog.md`](../upstream/starrocks/docs/en/data_source/catalog/hive_catalog.md)
- [`iceberg/iceberg.md`](../upstream/starrocks/docs/en/data_source/catalog/iceberg/iceberg.md)
- [`feature-support-data-lake-analytics.md`](../upstream/starrocks/docs/en/data_source/feature-support-data-lake-analytics.md)
- [`data_cache.md`](../upstream/starrocks/docs/en/data_source/data_cache/data_cache.md)
- [`data_cache_observe.md`](../upstream/starrocks/docs/en/data_source/data_cache/data_cache_observe.md)
