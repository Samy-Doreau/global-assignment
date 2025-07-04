# Production Overview – Podcast Analytics Pipeline

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
