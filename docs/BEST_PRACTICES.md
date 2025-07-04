# Podcast Analytics Pipeline - Best practices overview

## Best-Practice Matrix

| Requirement                 | Design Decision                                                                                                                     |
| --------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Modular design              | dbt folders: `1.staging`, `2.intermediate`, `3.marts` – isolation of cleansing, business logic & reporting                          |
| Readability                 | Snake-case SQL, one CTE per concern, extensive inline comments                                                                      |
| Error handling & resilience | Firehose retry + S3 DLQ for bad JSON; Snowpipe validates file atomicity; invalid events quarantined in `stg_user_events_invalid`    |
| Performance                 | Snowflake X-Small warehouse with auto-suspend; incremental materialisations on large facts; clustering on `(event_date,event_type)` |
| Scalability                 | Partitioned S3 buckets (`raw_events/yyyymmdd/`), Kinesis scaling, Snowflake warehouses scale-out; dbt incremental + streams/tasks   |
| Testing strategy            | dbt tests: `not_null`, `unique`, `accepted_values`, bespoke DQ counts; CI step fails PR on test errors                              |
| Reusability                 | Parameterised Terraform modules; dbt macros (`generate_surrogate_key`, session logic)                                               |
| Documentation               | dbt docs site – lineage graph; markdown in repo                                                                                     |
| Onboarding                  | One-line `make pipeline` for end-to-end run; detailed READMEs per folder                                                            |
| Governance                  | GitHub Actions audit trail; Snowflake access roles; dbt artefacts stored for 30 days                                                |

---

## High-level Architecture

```mermaid
%%< include diagrams/architecture.mmd >%%
```

---

## Component Catalogue

| Layer         | AWS / Snowflake Resource             | Purpose                                      |
| ------------- | ------------------------------------ | -------------------------------------------- |
| Ingestion     | **Kinesis Data Firehose**            | Buffer & deliver JSON events, handle retries |
| Landing       | **S3 – raw bucket**                  | Durable, versioned store of daily partitions |
| Loader        | **Snowpipe + S3 Event Notification** | Auto-ingest new objects into Snowflake stage |
| Storage       | **Snowflake Warehouse (X-Small)**    | Compute for raw & staging models             |
| Transform     | **dbt Cloud Job**                    | Runs incremental models & tests on schedule  |
| Orchestration | **Managed Airflow DAG**              | Coordinates Loader→dbt→exports               |

---

## CI / CD & IaC Workflow

1. **Pull Request** ➜ GitHub Actions:
   - `terraform fmt` / `tflint`
   - `terraform plan` (dev)
   - `dbt build --target ci` (all tests)
2. **Merge** ➜ `terraform apply` (dev) via OIDC.
3. **Tag** ➜ `terraform plan/apply` (prod) with manual approval.
4. dbt Cloud is triggered via API; artefacts (manifest, logs) pushed back to S3 for audit.

## Design Rationale & Deep-dives

### Why cluster by `event_date, event_type`?

`event_date` is derived in dbt as `date_trunc('day', event_ts)` and is **persisted in the fact table** once the model is materialised as an incremental table (e.g. `fact_user_events`).
Most dashboards slice by _date_ and _event_type_ – clustering on those columns lets Snowflake prune partitions when users run:

```sql
SELECT COUNT(*)
FROM   fact_user_events
WHERE  event_date = '2025-07-01'
  AND  event_type  = 'complete';
```

It **does not** help joins (those are on surrogate keys) but it speeds the high-volume _filter_ workload that underpins KPI tiles.

### Incremental materialisation & CDC for dimensions

- **Fact feed** – append-only, so dbt `incremental` with `is_incremental()` works out-of-the-box.
- **Dimensions (users / episodes)** – may _change_ (country moves, title edits). We would:
  1. Land nightly CSV extracts.
  2. Use **dbt snapshots** (`strategy: check`) to capture history in slowly-changing tables.
  3. Transform into type-2 dimension views consumed by marts.

### Orchestration with Airflow

A managed Airflow DAG (see Component Catalogue) provides dependency management:

1. **Sensor** task polls Snowpipe's `SYSTEM$PIPE_STATUS()` until yesterday's files are fully ingested.
2. **dbt Cloud Trigger** task hits the Cloud API to run the job once raw load is confirmed.
3. **Export** tasks copy mart CSVs back to S3 / Share.
   This guarantees the warehouse never queries half-loaded days.

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

### Role-based access control (RBAC)

```
SECURITY_ADMIN
└─ ANALYTICS_ROLE          -- human analysts (read marts)
└─ TRANSFORM_ROLE          -- dbt Cloud (create in analytics DB)
└─ LOAD_ROLE               -- Snowpipe & Firehose stages
```

Each technical role owns the least privileges required and is granted to service or human users through higher-level roles – aligning with the governance requirement in the PDF.
