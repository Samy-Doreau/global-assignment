# Data Modeling for Podcast Analytics

## Overview & Approach

We now materialise the fact as `fact_user_events` (table in `3.marts`) and expose two dimensions `dim_users`, `dim_episodes`. Joins:

- `fact_user_events.user_id` → `dim_users.user_id`
- `fact_user_events.episode_id` → `dim_episodes.episode_id`

### Updated star-schema

```mermaid
graph TD
  F[fact_user_events] -- user_id --> DU[dim_users]
  F -- episode_id --> DE[dim_episodes]
  F -- session_id *> DS[dim_sessions] %% derived from int_user_sessions
```

### Revised dbt Layering

1. **staging** – `stg_*` views (schema-on-read)
2. **intermediate** – `int_user_sessions` (sessionisation)
3. **marts** – `fact_user_events`, `dim_users`, `dim_episodes`, plus KPI marts

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

## Assumptions & Next Steps

- **Time zone** – all timestamps are normalised to UTC in staging.
- **Session rule** – a new session starts after ≥30 minutes of inactivity.
- **Partial plays** – a _play_ without a matching _complete_ still counts as one
  _play_; completion rate is computed accordingly.
- The model can be extended to capture **ad impression** events, **device**
  dimensions, or a **slowly changing episodes** table if show metadata evolves.

---

Continue reading the inline comments in each SQL model for deeper context.

### Why derive sessions?

The assignment calls for metrics such as **average session duration per user** – a classic streaming‐app KPI. A _session_ groups consecutive events separated by no more than 30 minutes of inactivity. Computing this in an **intermediate** model keeps the heavy window-function logic out of the thin marts and makes the session table reusable by multiple downstream marts (e.g. churn analysis, retention curves).

Even if a stakeholder only asked for _top completed episodes_ today, surfacing `int_user_sessions` future-proofs the model; new questions about "time spent listening" can be answered without rewriting raw logic.
