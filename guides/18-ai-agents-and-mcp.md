# 18. AI agents and MCP

How to let AI agents and assistants query a StarRocks cluster safely.

## The official MCP server

StarRocks maintains a Model Context Protocol server:

- Repository: https://github.com/StarRocks/mcp-server-starrocks (Apache-2.0)
- Package: `mcp-server-starrocks`
- Upstream quick start in this repository: [`quick_start/MCP.md`](../upstream/starrocks/docs/en/quick_start/MCP.md)

The server's code and README are not copied here. What follows describes version 0.4.0 as read from its repository. Check the current README before relying on any detail.

### What it exposes

| Tool | Does |
|---|---|
| `read_query` | Runs `SELECT`, `SHOW`, `DESCRIBE`. Can write large results to a file on the server instead of returning them inline. |
| `write_query` | Runs DDL and DML |
| `analyze_query` | Returns a query profile or `EXPLAIN ANALYZE` |
| `table_overview`, `db_overview` | Columns, row count and sample rows, cached in memory |
| `query_and_plotly_chart` | Runs a query and builds a chart from a Python expression supplied by the caller |
| Resources | `starrocks://` for schemas, `proc://` for internal state |

### How it connects

- To the FE over the MySQL protocol on port 9030. Optionally over Arrow Flight SQL.
- Transports: Streamable HTTP, or stdio.
- Configuration is by environment variable: `STARROCKS_URL`, or `STARROCKS_HOST`, `STARROCKS_PORT`, `STARROCKS_USER`, `STARROCKS_PASSWORD`, `STARROCKS_DB`.
- Useful extras: `STARROCKS_PASSWORD_FILE`, `STARROCKS_QUERY_TIMEOUT`, `STARROCKS_SSL_CA`, `STARROCKS_SSL_CERT`, `STARROCKS_SSL_KEY`, `STARROCKS_SSL_VERIFY_CERT`, `STARROCKS_SSL_VERIFY_IDENTITY`, `STARROCKS_MYSQL_AUTH_PLUGIN`.

### Running it on Kubernetes

Run it as a small Deployment next to the cluster, in Streamable HTTP mode, pointed at the FE service:

```yaml
env:
  - {name: STARROCKS_HOST, value: sr-fe-service.starrocks.svc.cluster.local}
  - {name: STARROCKS_PORT, value: "9030"}
  - {name: STARROCKS_USER, value: svc_agent}
  - {name: STARROCKS_PASSWORD_FILE, value: /var/run/secrets/starrocks/password}
  - {name: STARROCKS_QUERY_TIMEOUT, value: "300"}
```

Mount the password from a Secret as a file.

## Hardening checklist

Points to check against the version you deploy:

| Risk | Control |
|---|---|
| `write_query` is exposed, and the server has no read-only switch | Enforce read-only **in StarRocks**. Give the agent's database user `SELECT` only. Remove the tool in a fork if your policy requires it. |
| The chart tool evaluates a caller-supplied Python expression | Treat it as code execution inside the MCP pod. Remove the tool, or sandbox the pod: non-root, read-only filesystem, no ServiceAccount token, tight network policy. |
| The HTTP endpoint has no authentication of its own | Put it behind your gateway or mesh. Do not expose it on a public address. |
| No query timeout unless you set one | Set `STARROCKS_QUERY_TIMEOUT`, and rely on resource group limits as the real backstop |
| TLS to FE does not verify the server certificate by default | Set `STARROCKS_SSL_CA` and turn on `STARROCKS_SSL_VERIFY_CERT` and `STARROCKS_SSL_VERIFY_IDENTITY` |
| One shared database login | Every agent appears as the same user in the audit log. Run one instance per agent identity if you need attribution. |
| Result files are written on the server | Set `STARROCKS_MCP_OUTPUT_DIR` to a bounded volume, or do not use `output_file` |

## Guardrails in StarRocks

These apply to any automated caller, whether it uses MCP or a plain driver.

### A dedicated, read-only identity

```sql
CREATE USER 'svc_agent'@'%' IDENTIFIED BY '<password>';
CREATE ROLE agent_readonly;

GRANT USAGE ON CATALOG hive_glue TO ROLE agent_readonly;
SET CATALOG hive_glue;
GRANT SELECT ON ALL TABLES IN ALL DATABASES TO ROLE agent_readonly;

GRANT agent_readonly TO USER 'svc_agent'@'%';
SET DEFAULT ROLE agent_readonly TO 'svc_agent'@'%';
```

Grant only the databases the agent should see.

### A resource group with hard limits

Generated SQL will sooner or later omit a partition filter on a very large table.

```sql
CREATE RESOURCE GROUP rg_agents
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

Queries that cross a `big_query_*` limit are terminated. Set the numbers from real queries in the audit log. See [Resource management](11-resource-management.md).

### Admission control

Turn on query queues so a burst of agent queries waits instead of overloading the cluster.

### Cheaper answers

- Build materialized views for the aggregates agents ask for most. Queries are rewritten to use them without changes to the SQL.
- Give the agent `table_overview` style context, or a short schema description, so it writes partition filters.

### Observability

- The audit log records user, statement, scan rows, CPU cost and resource group for every query.
- Alert on queries killed by big-query limits and on queue wait time for the agent group.

## Agents that speak Trino SQL

If an agent or its prompts were written for Trino:

```sql
SET GLOBAL sql_dialect = 'trino';
```

This changes the default for new sessions cluster-wide. Use session scope, `SET sql_dialect = 'trino';`, if only some callers need it. See [`TRANSLATE_TRINO.md`](../upstream/starrocks/docs/en/sql-reference/sql-statements/TRANSLATE_TRINO.md) to check how a statement is translated.

## A worked example upstream

AWS Data on EKS has an `agentic-analytics` example under `data-stacks/starrocks-on-eks/examples/` in its repository, with an agent, an MCP server image and a seed job. It is application code and is not copied here.

## Upstream sources

- [`quick_start/MCP.md`](../upstream/starrocks/docs/en/quick_start/MCP.md)
- [`resource_group.md`](../upstream/starrocks/docs/en/administration/management/resource_management/resource_group.md)
- [`administration/user_privs/`](../upstream/starrocks/docs/en/administration/user_privs/)
