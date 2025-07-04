# Data Modeling for Podcast Analytics

## Overview & Approach

We adopt a classic **star-schema** to keep analytics queries simple and fast.
The centre of the star is an **event fact table** – each row is a specific
interaction a user performed while listening to a podcast episode. Surrounding
the fact are a handful of slowly-changing **dimension** tables (users,
episodes, date/time, and derived sessions). This layout offers:

1.  High read-performance for BI-style aggregations.
2.  Clear separation between _raw_, _cleaned_ and _business_ layers in dbt.
3.  Flexibility to bolt-on new dimensions or facts without breaking consumers.

```
              +-------------+
              |  dim_users  |
              +-------------+
                    |
+---------+   +-------------+   +---------------+
| dim_date|---| fact_events |---| dim_episodes  |
+---------+   +-------------+   +---------------+
                    |
              +----------------+
              | dim_sessions  |
              +----------------+
```

### Event Types

The raw JSON events arriving in our data lake conform to four canonical event
shapes:

| type       | semantics                                | has `duration`? |
| ---------- | ---------------------------------------- | --------------- |
| `play`     | user pressed _play_ or resumed playback  | yes             |
| `pause`    | user paused the stream                   | no              |
| `seek`     | user jumped to a different timestamp     | no              |
| `complete` | playback reached (near-)100 % of episode | yes             |

Example payloads (JSONL):

```jsonc
// play
{"user_id": 7, "episode_id": 42, "ts": "2025-07-01T12:00:00Z", "type": "play", "duration": 180}
// pause
{"user_id": 7, "episode_id": 42, "ts": "2025-07-01T12:03:00Z", "type": "pause"}
// seek
{"user_id": 7, "episode_id": 42, "ts": "2025-07-01T12:03:05Z", "type": "seek", "seek_to": 900}
// complete
{"user_id": 7, "episode_id": 42, "ts": "2025-07-01T12:30:00Z", "type": "complete", "duration": 1800}
```

Only `play` and `complete` events carry a _duration_ field indicating seconds
of uninterrupted listening.

## dbt Layering Strategy

1. **staging** – one-to-one cleanses of raw files.
   - `stg_user_events` (JSON → typed columns)
   - `stg_users`, `stg_episodes` (CSV references)
2. **intermediate** – logic-heavy, reusable models.
   - `int_user_sessions` – sessionise events using a 30-minute inactivity gap.
3. **marts** – final business-friendly tables / views.
   - `mart_top_episodes`
   - `mart_user_session_metrics`

Materialisation defaults to `view` to keep the warehouse footprint light during
iteration; switch to `table` or incremental later if needed.

## Generate an Entity-Relationship Diagram (ERD)

An ERD visually shows how your data models connect to each other - think of it as a "map" of your database structure. This is incredibly useful for:

- **Understanding relationships**: See which tables join to which others
- **Documentation**: Share with stakeholders who prefer visual diagrams
- **Onboarding**: Help new team members understand the data architecture
- **Validation**: Verify your model design matches your intentions

### How to generate the ERD:

```bash
# 1. Install dependencies (includes dbt-erd and graphviz)
pip install -r requirements.txt

# 2. Build your dbt models first (so dbt-erd can analyze them)
cd dbt
dbt deps
dbt run

# 3. Generate the visual diagram
dbt-erd render models/ --output ../docs/erd.svg
```

The `erd.svg` file will show:

- **Tables** as boxes with their columns
- **Relationships** as connecting lines (foreign keys, joins)
- **Data types** for each column
- **Model dependencies** (staging → intermediate → marts)

You can open `docs/erd.svg` in any web browser to view the diagram, or include it in documentation.

## Assumptions & Next Steps

- **Time zone** – all timestamps are normalised to UTC in staging.
- **Session rule** – a new session starts after ≥30 minutes of inactivity.
- **Partial plays** – a _play_ without a matching _complete_ still counts as one
  _play_; completion rate is computed accordingly.
- The model can be extended to capture **ad impression** events, **device**
  dimensions, or a **slowly changing episodes** table if show metadata evolves.

---

Continue reading the inline comments in each SQL model for deeper context.
