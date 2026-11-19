-- External catalogs over an S3 data lake registered in AWS Glue.
--
-- Original example written for this repository. Replace every <placeholder>.
-- See guides/10-data-lake-on-s3-and-glue.md
--
-- Prerequisite: FE and CN pods run under a ServiceAccount whose IAM role can
-- read the Glue Data Catalog and the S3 buckets.

-- ---------------------------------------------------------------------------
-- 1. Hive-style tables (Parquet, ORC, text) in Glue
-- ---------------------------------------------------------------------------
CREATE EXTERNAL CATALOG hive_glue
COMMENT "Hive tables in AWS Glue, default metadata cache"
PROPERTIES
(
    "type" = "hive",
    "hive.metastore.type" = "glue",
    "aws.glue.use_instance_profile" = "true",
    "aws.glue.region" = "<region>",
    "aws.s3.use_instance_profile" = "true",
    "aws.s3.region" = "<region>"
);

-- The same lake with fresher metadata, for jobs that must see new files
-- quickly. Shorter refresh intervals mean more Glue and S3 list calls.
CREATE EXTERNAL CATALOG hive_glue_fresh
COMMENT "Hive tables in AWS Glue, short metadata cache"
PROPERTIES
(
    "type" = "hive",
    "hive.metastore.type" = "glue",
    "aws.glue.use_instance_profile" = "true",
    "aws.glue.region" = "<region>",
    "aws.s3.use_instance_profile" = "true",
    "aws.s3.region" = "<region>",
    "metastore_cache_refresh_interval_sec" = "30",
    "remote_file_cache_refresh_interval_sec" = "30"
);

-- Cross-account Glue catalog, assuming a role in the other account.
-- CREATE EXTERNAL CATALOG hive_glue_xacct
-- PROPERTIES
-- (
--     "type" = "hive",
--     "hive.metastore.type" = "glue",
--     "hive.metastore.glue.catalogid" = "<other-account-id>",
--     "aws.glue.use_instance_profile" = "true",
--     "aws.glue.iam_role_arn" = "arn:aws:iam::<other-account-id>:role/<role>",
--     "aws.glue.region" = "<region>",
--     "aws.s3.use_instance_profile" = "true",
--     "aws.s3.iam_role_arn" = "arn:aws:iam::<other-account-id>:role/<role>",
--     "aws.s3.region" = "<region>"
-- );

-- ---------------------------------------------------------------------------
-- 2. Iceberg tables in Glue
-- ---------------------------------------------------------------------------
CREATE EXTERNAL CATALOG iceberg_glue
PROPERTIES
(
    "type" = "iceberg",
    "iceberg.catalog.type" = "glue",
    "aws.glue.use_instance_profile" = "true",
    "aws.glue.region" = "<region>",
    "aws.s3.use_instance_profile" = "true",
    "aws.s3.region" = "<region>"
);

-- ---------------------------------------------------------------------------
-- 3. Look around
-- ---------------------------------------------------------------------------
SHOW CATALOGS;
SHOW DATABASES FROM hive_glue;

SET CATALOG hive_glue;
USE <database>;
SHOW TABLES;
DESC <table>;

-- Always filter on the partition column.
SELECT count(*)
FROM hive_glue.<database>.<table>
WHERE <partition_column> = '<value>';

-- ---------------------------------------------------------------------------
-- 4. Freshness
-- ---------------------------------------------------------------------------
-- Pick up new files or partitions now, without waiting for the refresh.
REFRESH EXTERNAL TABLE hive_glue.<database>.<table>;
REFRESH EXTERNAL TABLE hive_glue.<database>.<table> PARTITION ('<partition_column>=<value>');

-- ---------------------------------------------------------------------------
-- 5. Statistics, for better join planning
-- ---------------------------------------------------------------------------
ANALYZE TABLE hive_glue.<database>.<table>;

-- ---------------------------------------------------------------------------
-- 6. Read-only access for a role
-- ---------------------------------------------------------------------------
CREATE ROLE lake_readonly;
GRANT USAGE ON CATALOG hive_glue TO ROLE lake_readonly;
SET CATALOG hive_glue;
GRANT SELECT ON ALL TABLES IN ALL DATABASES TO ROLE lake_readonly;
SET CATALOG default_catalog;

-- ---------------------------------------------------------------------------
-- 7. A daily rollup as a materialized view (stored as a native table)
-- ---------------------------------------------------------------------------
-- Materialized views can only be created in default_catalog (set above).
CREATE DATABASE IF NOT EXISTS mv;

-- CREATE MATERIALIZED VIEW default_catalog.mv.<table>_daily
-- PARTITION BY <partition_column>
-- REFRESH ASYNC EVERY (INTERVAL 1 HOUR)
-- AS
-- SELECT <partition_column>, <dimension>, count(*) AS row_count
-- FROM hive_glue.<database>.<table>
-- GROUP BY <partition_column>, <dimension>;

-- ---------------------------------------------------------------------------
-- 8. Warm the data cache for recent data
-- ---------------------------------------------------------------------------
-- CACHE SELECT <column_a>, <column_b>
-- FROM hive_glue.<database>.<table>
-- WHERE <partition_column> >= '<value>';

-- ---------------------------------------------------------------------------
-- 9. Clean up
-- ---------------------------------------------------------------------------
-- DROP CATALOG hive_glue_fresh;
