-- int_user_sessions.sql : derive user listening sessions

-- 1. Bring in all user events from the staging model
with events as (
    select * from {{ ref('stg_user_events') }}
),

-- 2. For each event, get the timestamp of the previous event for the same user
events_with_lag as (
    select
        *,
        lag(event_ts) over (partition by user_id order by event_ts) as previous_event_ts
    from events
),

-- 3. Flag the start of a new session:
--    - If there is no previous event (first event for user)
--    - Or if the gap between events is more than 30 minutes
flagged as (
    select
        *,
        case
            when previous_event_ts is null
              or extract(epoch from (event_ts - previous_event_ts))/60 > 30
            then 1 else 0 end as new_session_flag
    from events_with_lag
),

-- 4. Assign a session number to each event for each user by cumulatively summing the new session flags
numbered as (
    select
        *,
        sum(new_session_flag) over (partition by user_id order by event_ts) as session_number
    from flagged
),

-- 5. Aggregate events into sessions:
--    - Find session start/end timestamps
--    - Sum up listening duration for the session
agg as (
    select
        user_id,
        session_number,
        min(event_ts) as session_start,
        max(event_ts) as session_end,
        sum(coalesce(duration, 0)) as total_listening_duration
    from numbered
    group by user_id, session_number
),

-- 6. Generate a surrogate session_id and select final session fields
final as (
    select
        {{ dbt_utils.generate_surrogate_key(['user_id', 'session_number']) }} as session_id,
        user_id,
        session_start,
        session_end,
        total_listening_duration as session_duration
    from agg
)

-- 7. Output the final sessionized data
select * from final