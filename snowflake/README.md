# Snowflake Optimisation & Automation

## Clustering

For the large `fact_user_events` (or its view) create clustering keys to speed up filters on event time & type:

```sql
ALTER TABLE fact_user_events CLUSTER BY (event_date, event_type);
```

Snowflake will maintain micro-partition metadata so queries such as

```sql
SELECT COUNT(*) FROM fact_user_events WHERE event_date = '2025-07-01'
```

prune partitions efficiently.

## Search Optimisation Service

If ad-hoc analysts frequently filter on `user_id` (high-cardinality) enable SOS:

```sql
ALTER TABLE fact_user_events SET SEARCH_OPTIMIZATION = ON;
```

Gives sub-second point look-ups without over-clustering.

## Streams & Tasks pattern

```sql
-- Stream captures new rows inserted via Snowpipe
CREATE OR REPLACE STREAM fact_user_events_stream ON TABLE raw_event_files;

-- Task runs every 5 minutes loading incrementally into staging
CREATE OR REPLACE TASK load_user_events
  WAREHOUSE = analytics_xs
  SCHEDULE  = '5 MINUTE'
AS
INSERT INTO fact_user_events
SELECT * FROM raw_event_files WHERE metadata$action = 'INSERT';
```

Couple this with a scheduled **dbt Cloud Job** that runs incremental models after the task finishes.

## Warehouse sizing

Start with `XSMALL`, auto-suspend after 60 s idle:

```sql
ALTER WAREHOUSE analytics_xs SET AUTO_SUSPEND = 60;
```

Enable auto-resume and auto-suspend on warehouses.
