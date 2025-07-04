-- int_user_sessions.sql : derive user listening sessions
with events as (
    select * from {{ ref('stg_user_events') }}
),

flagged as (
    select
        *,
        case
            when lag(event_ts) over (partition by user_id order by event_ts) is null
              or datediff('minute', lag(event_ts) over (partition by user_id order by event_ts), event_ts) > 30
            then 1 else 0 end as new_session_flag
    from events
),

numbered as (
    select
        *,
        sum(new_session_flag) over (partition by user_id order by event_ts) as session_number
    from flagged
),

agg as (
    select
        {{ dbt_utils.generate_surrogate_key(['user_id', 'session_number']) }} as session_id,
        user_id,
        min(event_ts) as session_start,
        max(event_ts) as session_end,
        datediff('second', min(event_ts), max(event_ts)) as session_duration
    from numbered
    group by user_id, session_number
)
select * from agg; 