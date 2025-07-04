# Data Modeling for Podcast Analytics

## Overview & Approach

We adopt a classic **star-schema** centred on an **event fact table** (`stg_user_events`). Around this fact we expose slowly-changing **dimensions**:

```
              +-------------+
              |  dim_users  |  <-- stg_users
              +-------------+
                    |
+---------+   +------------------+   +---------------+
| dim_date|---|  fact_user_events|---| dim_episodes  |
+---------+   +------------------+   +---------------+
                    |
              +----------------+
              |  dim_sessions  |  <-- int_user_sessions
              +----------------+
```

Note: the fact is currently materialised as a _view_ called `stg_user_events`; in a production warehouse we would implement this as an incremental table (e.g. `fact_user_events`) to ensure performance is adequate.

### Event Types & JSON shape (actual fields)

The raw line-delimited JSON arriving in the landing bucket uses these canonical fields:

| field        | example value                       | notes                                  |
| ------------ | ----------------------------------- | -------------------------------------- |
| `user_id`    | `user_42`                           | string ID                              |
| `episode_id` | `ep_155`                            | string ID                              |
| `timestamp`  | `2025-07-01T12:00:00Z`              | ISO-8601, always UTC                   |
| `event_type` | `play \| pause \| seek \| complete` | enum of 4 types                        |
| `duration`   | `180`                               | seconds; only on _play_ and _complete_ |

Example payloads:

```jsonc
// play
{"user_id":"user_1","episode_id":"ep_1","timestamp":"2025-07-01T12:00:00Z","event_type":"play","duration":120}
// pause
{"user_id":"user_1","episode_id":"ep_1","timestamp":"2025-07-01T12:02:00Z","event_type":"pause"}
// seek
{"user_id":"user_2","episode_id":"ep_5","timestamp":"2025-07-02T09:20:00Z","event_type":"seek","seek_to":600}
// complete
{"user_id":"user_2","episode_id":"ep_5","timestamp":"2025-07-02T09:45:00Z","event_type":"complete","duration":1800}
```

We land data into Postgres (via `scripts/load_events_to_postgres.py`) using a **schema-on-read** approach with three fields:

- `data` - JSON payload containing the complete event record
- `source_file_name` - indicates which source file the record came from
- `source_file_loaded_at` - timestamp when the batch was loaded

This approach builds resilience against schema changes by encapsulating the entire record within a JSON payload. dbt then extracts fields from the JSON column during transformation. When the source schema evolves, we can simply add new field extractions to the dbt models without breaking existing pipelines or requiring data reloads.

### dbt Layering (exact project structure)

1. **staging** (models/1.staging)
   - `stg_user_events` – JSON → typed columns (fact)
   - `stg_users` / `stg_episodes` – reference CSVs (dimensions)
   - `stg_user_events_invalid` – quarantines bad rows for data-quality review
2. **intermediate** (models/2.intermediate)
   - `int_user_sessions` – derives sessions using 30-min inactivity rule
3. **marts** (models/3.marts)
   - `mart_top_episodes` – episode-level engagement metrics
   - `mart_user_session_metrics` – user-level session KPIs

Materialisations are `view` by default; switch to `table`/`incremental` once volume grows.

## Assumptions & Next Steps

- **Time zone** – all timestamps are normalised to UTC in staging.
- **Session rule** – a new session starts after ≥30 minutes of inactivity.
- **Partial plays** – a _play_ without a matching _complete_ still counts as one
  _play_; completion rate is computed accordingly.
- The model can be extended to capture **ad impression** events, **device**
  dimensions, or a **slowly changing episodes** table if show metadata evolves.

---

Continue reading the inline comments in each SQL model for deeper context.
