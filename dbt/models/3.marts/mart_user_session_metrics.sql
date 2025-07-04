-- mart_user_session_metrics.sql : user level session KPIs
with sessions as (
    select * from {{ ref('int_user_sessions') }}
),

metrics as (
    select
        user_id,
        avg(session_duration) as avg_session_duration,
        count(*) as sessions,
        cast(min(session_start) as date) as first_session_date,
        cast(max(session_end) as date) as last_session_date
    from sessions
    group by user_id
)
select * from metrics