-- int_user_sessions.sql : derive user listening sessions
with events as (
    select * from {{ ref('stg_user_events') }}
),

events_with_lag as (
    select
        *,
        lag(event_ts) over (partition by user_id order by event_ts) as previous_event_ts
    from events
),

flagged as (
    select
        *,
        case
            when previous_event_ts is null
              or extract(epoch from (event_ts - previous_event_ts))/60 > 30
            then 1 else 0 end as new_session_flag
    from events_with_lag
),

numbered as (
    select
        *,
        sum(new_session_flag) over (partition by user_id order by event_ts) as session_number
    from flagged
),

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

final as (
    select
        {{ dbt_utils.generate_surrogate_key(['user_id', 'session_number']) }} as session_id,
        user_id,
        session_start,
        session_end,
        total_listening_duration as session_duration
    from agg
)

select * from final