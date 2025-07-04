-- stg_user_events.sql : typed raw event records from JSONB
-- Note: Invalid events are captured in stg_user_events_invalid.sql for investigation
with source as (
    select data
    from {{ source('raw', 'event_files') }}
),

valid_events as (
    select * from source
    where data ->> 'event_type' is not null
      and data ->> 'event_type' in ('play', 'pause', 'seek', 'complete')
      and data ->> 'timestamp' is not null
      and data ->> 'timestamp' != ''
      and data ->> 'user_id' is not null
      and data ->> 'episode_id' is not null
),

typed as (
    select
        {{ dbt_utils.generate_surrogate_key([
            "data ->> 'user_id'",
            "data ->> 'episode_id'",
            "data ->> 'timestamp'",
            "data ->> 'event_type'"
        ]) }} as event_id,
        data ->> 'user_id'      as user_id,
        data ->> 'episode_id'   as episode_id,
        case 
            when (data ->> 'timestamp') ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}' then (data ->> 'timestamp')::timestamp
            else null
        end as event_ts,
        data ->> 'event_type'         as event_type,
        (data ->> 'duration')::integer as duration
    from valid_events
    where (data ->> 'timestamp') ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}'
)
select * from typed 