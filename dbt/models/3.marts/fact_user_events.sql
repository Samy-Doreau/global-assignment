{{ config(materialized='table') }}
-- fact_user_events.sql : central fact table of cleaned user events with de-duplication on event_id

with base as (
    select *
    from {{ ref('stg_user_events') }}
),

dedup as (
    select
        *,
        row_number() over (partition by event_id order by event_ts desc nulls last) as rn
    from base
)

select
    event_id as "Event ID",
    event_ts as "Event Timestamp",
    user_id as "User ID",
    episode_id as "Episode ID",
    event_type as "Event Type",
    duration as "Duration"
from dedup
where rn = 1 