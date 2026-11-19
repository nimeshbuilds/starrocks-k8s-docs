-- Resource groups for three workloads sharing one cluster:
-- interactive users, scheduled jobs, and automated or agent-driven queries.
--
-- Original example written for this repository.
-- See guides/11-resource-management.md
--
-- Every number here is a placeholder. Size them from your node shape and from
-- real queries in fe.audit.log (PlanCpuCost, scan rows, memory).
-- All limits are per BE/CN node.

-- ---------------------------------------------------------------------------
-- Identities. Classifiers match on user or role, so each workload needs its own.
-- ---------------------------------------------------------------------------
CREATE ROLE analyst;
CREATE USER 'svc_scheduler'@'%' IDENTIFIED BY '<password>';
CREATE USER 'svc_agent'@'%'     IDENTIFIED BY '<password>';

-- ---------------------------------------------------------------------------
-- Interactive: the largest share, moderate concurrency.
-- ---------------------------------------------------------------------------
CREATE RESOURCE GROUP rg_interactive
TO (role='analyst', query_type in ('select'))
WITH (
    'cpu_weight' = '8',
    'mem_limit' = '50%',
    'concurrency_limit' = '30'
);

-- ---------------------------------------------------------------------------
-- Scheduled jobs: a steady share that the other groups cannot take away
-- under contention.
-- ---------------------------------------------------------------------------
CREATE RESOURCE GROUP rg_scheduled
TO (user='svc_scheduler')
WITH (
    'cpu_weight' = '6',
    'mem_limit' = '40%',
    'concurrency_limit' = '50'
);

-- ---------------------------------------------------------------------------
-- Automated callers: a small share, with hard caps that terminate runaway
-- queries (for example a scan with no partition filter).
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- Everything else lands in default_wg. Optionally cap it too.
-- ---------------------------------------------------------------------------
-- ALTER RESOURCE GROUP default_wg WITH ('concurrency_limit' = '20');

-- ---------------------------------------------------------------------------
-- Inspect
-- ---------------------------------------------------------------------------
SHOW RESOURCE GROUPS ALL;

-- Which group would this query use?
-- EXPLAIN VERBOSE SELECT ...;

-- ---------------------------------------------------------------------------
-- Admission control: queue instead of overload.
-- ---------------------------------------------------------------------------
SET GLOBAL enable_query_queue_select = true;
SET GLOBAL enable_query_queue_statistic = true;
-- SET GLOBAL query_queue_concurrency_limit = 100;
-- SET GLOBAL query_queue_mem_used_pct_limit = 0.85;
SET GLOBAL query_queue_max_queued_queries = 1024;
SET GLOBAL query_queue_pending_timeout_second = 300;

-- ---------------------------------------------------------------------------
-- Spill to disk for large joins and aggregations.
-- Requires spill_local_storage_dir in cn.conf / be.conf.
-- ---------------------------------------------------------------------------
-- SET GLOBAL enable_spill = true;
-- SET GLOBAL spill_mode = 'auto';

-- ---------------------------------------------------------------------------
-- Change or remove
-- ---------------------------------------------------------------------------
-- ALTER RESOURCE GROUP rg_automation WITH ('big_query_scan_rows_limit' = '100000000000');
-- ALTER RESOURCE GROUP rg_interactive ADD (user='power_user');
-- DROP RESOURCE GROUP rg_automation;
