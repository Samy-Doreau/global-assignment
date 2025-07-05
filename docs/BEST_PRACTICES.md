# Podcast Analytics Pipeline – Best-Practices Walk-through

> This repository purposefully **trades completeness for clarity**. It is a very simplified solution that can be run on a laptop in minutes. The choices below therefore focus on demonstrating best-practice _patterns_ rather than building a fully-hardened, cloud-native stack.

---

## 1 How the demo addresses best-practice criteria

| Area                            | What the local demo implements                                                                                                                                       |
| ------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Modular design**              | dbt folders: `1.staging` (schema-on-read JSON→columns), `2.intermediate` (session logic), `3.marts` (business metrics).                                              |
| **Readability**                 | Use of Snake-case, one CTE per concern, doc-blocks at the top of every SQL file, Makefile targets hide verbose commands.                                         |
| **Error handling & resilience** | `stg_user_events_invalid` quarantines missing / malformed rows; Makefile truncates raw tables before reload; JSON kept raw so unknown columns never break ingestion. |
| **Performance**                 | Staging models materialised as _views_; marts are materialised as _tables_ to ensure downstream BI tools are able to query the data fast; fact models join to stable dimensions, supporting Kimball-style star-schema queries.                                                     |
| **Scalability**                 | Schema-on-read pattern (source records are landed in postgres as JSON records) scales to new JSON fields without table rebuilds; sessionisation uses window functions.         |
| **Testing strategy**            | dbt tests: `not_null`, `unique`, `accepted_values`; Relationship tests implemented on marts to detect orphaned records, invalid-row counts are asserted in CI; `make dbt-debug` surfaces connectivity issues fast.                       |
| **Reusability**                 | Loader script takes any JSONL path; Make targets are parameterised (`FILE=...`);                                                 |
| **Documentation**               | Markdown READMEs per folder, automated production of dbt docs & elementary artifacts graph.                                                                                |
| **Onboarding**                  | One-liner `make pipeline` ensures new developers are able to get the project running locally quicky.                                                     |
| **Governance**                  | dbt manifests preserved; ERD + lineage provide impact analysis; Makefile enforces repeatable local runs.                                                             |


Limitations that would be solved in production (described in the next section):

- Single-node Postgres instead of Snowflake warehouse.
- Bash/Make orchestration instead of Airflow DAG.
- Manual ERD generation; no automated CI artefact storage.
- No SCD type-2 snapshots for dimensions


## 2 What a production-grade stack would add

The second half of this document sketches the _target_ architecture and operational safeguards we would put in place when running at a much larger scale.

### 2.1 Proposed high level architecture components


Key production additions compared with the demo:

- **Kinesis Firehose** to capture events from stream producers, batch them (by duration or size) and write to S3.
- **Snowpipe** provides _exactly-once_ ingestion semantics and auto-ingest on S3 event notifications.
- **Airflow DAG** waits for Snowpipe `SYSTEM$PIPE_STATUS()` = _LOADED_ before kicking off dbt.
- **dbt runs** we could use dbt Cloud, or dbt core on a github runner to keep costs low.
- **X-Small Warehouse** auto-suspends after 60 s idle; scale-out to Medium+ for backfills.
- **Search Optimisation Service** switched on for point look-ups by `user_id`.

### 2.2 Performance & scalability

- **fact_user_events** becomes an **incremental** table, clustered by `(event_date,event_type)` so daily + type filters prune micro-partitions.
- Streams + Tasks drive _UPSERT_ semantics → dbt runs only on changed days.
- Dimensions are tracked with **dbt snapshots** (type-2) so history is preserved without widening the fact.

### 2.3 IaC & deployment

- **Terraform** controls _both_ AWS (Firehose, S3) **and** Snowflake (roles, stages, pipes, warehouses). GitHub Actions runs `plan` on PR, `apply` on merge.
- Airflow DAGs are versioned alongside code; dbt Cloud job ID is stored in Terraform state – reproducible environments.

### 2.4 Security & RBAC

- Snowflake **network policy** restricts login to office/VPN CIDRs.
- **Key-pair auth** for service accounts; **MFA** for humans.
- Role hierarchy:
  ```
  SECURITY_ADMIN
  ├─ LOAD_ROLE        -- Snowpipe stages, streams
  ├─ TRANSFORM_ROLE   -- dbt Cloud warehouse & DB
  └─ ANALYTICS_ROLE   -- read marts
  ```
  Least-privilege grants and no cross-environment data leakage.



## Design Rationale & Deep-dives

### Performance gains from clustering fact table by `event_date, event_type`?

`event_date` is derived in dbt as `date_trunc('day', event_ts)` and is **persisted in the fact table** once the model is materialised as an incremental table (e.g. `fact_user_events`).
Dashboards are likely to slice by _date_ and _event_type_ – clustering on those columns lets Snowflake prune partitions when users run:

```sql
SELECT COUNT(*)
FROM   fact_user_events
WHERE  event_date = '2025-07-01'
  AND  event_type  = 'complete';
```

### Incremental materialisation & CDC for dimensions

- **Fact feed** – append-only, so dbt `incremental` with `is_incremental()` would be fairly straightforward to implement.
- **Dimensions (users / episodes)** – may _change_ (country moves, title edits). We would:
  1. Land nightly CSV extracts.
  2. Use **dbt snapshots** (`strategy: check`) to capture history in slowly-changing tables.
  3. Transform into type-2 dimension views consumed by marts.

### Orchestration with Airflow

A managed Airflow DAG (see Component Catalogue) provides dependency management:

1. **Sensor** task polls Snowpipe's `SYSTEM$PIPE_STATUS()` until yesterday's files are fully ingested.
2. **dbt Cloud Trigger** task hits the Cloud API to run the job once raw load is confirmed.
3. **Export** : trigger `unload` tasks export parts of mart tables back to s3 for further sharing or processing.

### Deployment pipeline

`github/workflows/ci.yml` (not shown in repo) would:

- Terraform → `plan` & `apply` (AWS + Snowflake) using OIDC.
- Airflow → DAG upload via `astro deploy` or MWAA API.
- dbt Cloud → job deployment via Cloud API.
  All actions gated by PR reviews and environments (`dev`, `prod`).

### Infrastructure as Code – Snowflake provider

The repo's `terraform/main.tf` already references the **Snowflake-Labs/snowflake** provider. Modules such as `modules/snowflake_warehouse` will create roles, warehouses, databases & streams—giving **single-source-of-truth** compliance.

### Security hardening

- **Network policies** – restrict logins to office / VPN CIDRs.
- **Key-pair auth** – service users authenticate via RSA keys stored in AWS Secrets Manager; passwords disabled.
- **MFA** – enforced for all human users via Snowflake MFA.


