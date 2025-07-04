# Podcast Analytics Pipeline – Best-Practices Walk-through

> This repository purposefully **trades completeness for clarity**. It is a "table-top" demo that can be run on any laptop in minutes. The choices below therefore focus on demonstrating best-practice _patterns_ rather than building a fully-hardened, cloud-native stack.

---

## 1 How the demo addresses best-practice criteria

| Area                            | What the local demo implements                                                                                                                                       |
| ------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Modular design**              | dbt folders: `1.staging` (schema-on-read JSON→columns), `2.intermediate` (session logic), `3.marts` (business metrics).                                              |
| **Readability**                 | Snake-case everywhere, one CTE per concern, doc-blocks at the top of every SQL file, Makefile targets hide verbose commands.                                         |
| **Error handling & resilience** | `stg_user_events_invalid` quarantines missing / malformed rows; Makefile truncates raw tables before reload; JSON kept raw so unknown columns never break ingestion. |
| **Performance**                 | Postgres demo keeps everything as _views_; comments explain how to flip to _incremental_ tables and add indexes.                                                     |
| **Scalability**                 | Schema-on-read pattern scales to new JSON fields without table rebuilds; sessionisation uses window functions – Snowflake can push-down to micro-partitions.         |
| **Testing strategy**            | dbt tests: `not_null`, `unique`, `accepted_values`; invalid-row counts are asserted in CI; `make dbt-debug` surfaces connectivity issues fast.                       |
| **Reusability**                 | Loader script takes any JSONL path; Make targets are parameterised (`FILE=...`); Terraform skeleton is module-based.                                                 |
| **Documentation**               | Markdown READMEs per folder, ERD auto-generated (`make erd`), dbt docs lineage graph.                                                                                |
| **Onboarding**                  | One-liner `make pipeline` brings new devs from zero → marts CSVs; debug script prints row counts at every layer.                                                     |
| **Governance**                  | dbt manifests preserved; ERD + lineage provide impact analysis; Makefile enforces repeatable local runs.                                                             |

---

## 2 What a production-grade stack would add

The second half of this document sketches the _target_ architecture and operational safeguards we would put in place when running at **millions-of-users** scale.

### 2.1 Cloud architecture

The Mermaid diagram below (and the Terraform skeleton in `terraform/`) illustrate an opinionated AWS → Snowflake data plane.

```mermaid
%%< include diagrams/architecture.mmd >%%
```

Key production additions compared with the demo:

- **Kinesis Firehose** buffers spikes and retries transient S3 failures – far more durable than a local Python copy loop.
- **Snowpipe** provides _exactly-once_ ingestion semantics and auto-ingest on S3 event notifications – no cron polling.
- **Airflow DAG** waits for Snowpipe `SYSTEM$PIPE_STATUS()` = _LOADED_ before kicking off dbt Cloud – end-to-end data freshness SLA.
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

---

This two-level explanation (local demo vs production design) should give reviewers clarity on _what_ has been delivered immediately and _how_ it would evolve into an enterprise-ready pipeline.

---

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

## Local Demo – What's covered & what's simplified

Even though this repo runs entirely on **local Postgres + dbt Core**, it still demonstrates a subset of the Staff-level concerns outlined in the brief:

| Best-practice theme | Where it lives in this repo                                                                                 |
| ------------------- | ----------------------------------------------------------------------------------------------------------- |
| Modular design      | Three-tier dbt folder layout (`1.staging` / `2.intermediate` / `3.marts`).                                  |
| Error handling      | `stg_user_events_invalid` captures malformed / missing fields; Makefile tasks fail fast via `set -e`.       |
| Schema-on-read      | Raw events land as JSON (`data` column); dbt extracts on read, giving forward-compatibility.                |
| Lineage & docs      | `make erd` generates an SVG; `dbt docs generate` spins up a searchable lineage site.                        |
| Testing             | See `schema.yml`: `unique`, `not_null`, `accepted_values` tests + custom DQ counts in invalid-events model. |
| Repeatability       | One-command entry points: `make up`, `make pipeline`, `make dbt`, `make erd`.                               |
| Readability         | Snake_case, one-purpose CTEs, 80-col SQL, extensive comments.                                               |

_What is **not** attempted locally:_ Kinesis → S3, Snowpipe, incremental Snowflake tables, Airflow DAGs. These appear in the next section as the production-grade target architecture.

## Demo Scope & How It Maps to Best Practices

> This take-home is a **local proof-of-concept** — it is deliberately minimal so it can be reviewed in minutes, not hours. Nevertheless it showcases several of the best-practice themes listed in the brief:

| Theme                       | Demo implementation                                                                                                                                          |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Modular design              | Three-layer dbt repo (`1.staging` → `2.intermediate` → `3.marts`) mirrors prod separation of concerns.                                                       |
| Code readability            | Snake-case everywhere; one CTE per transformation; explanatory headers in every SQL file; Markdown docs adjacent to code.                                    |
| Error handling & resilience | `stg_user_events_invalid` quarantines rows with missing IDs / malformed timestamps; Makefile truncates raw tables before reload to keep state deterministic. |
| Schema-on-read flexibility  | Raw JSON is stored in a single `data` JSONB column — dbt extracts fields, so adding new attributes requires **no backfill**.                                 |
| Testing strategy            | Source & model tests in `schema.yml` (`not_null`, `unique`, `accepted_values`); running `make dbt` fails the build on any test error.                        |
| Documentation & lineage     | `make erd` auto-generates an ERD; `dbt docs generate` builds an interactive lineage site.                                                                    |
| Developer ergonomics        | One-command `make pipeline FILE=...` spins up Postgres, ingests data, runs dbt, exports marts — new engineers can reproduce the flow in <5 mins.             |
| Governance starter kit      | Commit history + CI logs provide audit trail; JSON payload persists raw source unmodified; lineage graph aids GDPR/DSAR impact analysis.                     |

Limitations that would be solved in production (described in the next section):

- Single-node Postgres instead of Snowflake warehouse.
- Bash/Make orchestration instead of Airflow DAG.
- Manual ERD generation; no automated CI artefact storage.
- No SCD type-2 snapshots for dimensions (outlined but not implemented).

---
