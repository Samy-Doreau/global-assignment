-- stg_user_events_invalid.sql : capture invalid event records for investigation
with source as (
    select data
    from {{ source('raw', 'event_files') }}
),

invalid_events as (
    select 
        data,
        data ->> 'user_id' as user_id,
        data ->> 'episode_id' as episode_id,
        data ->> 'timestamp' as timestamp,
        data ->> 'event_type' as event_type,
        data ->> 'duration' as duration,
        case 
            when data ->> 'event_type' is null then 'missing_event_type'
            when data ->> 'event_type' not in ('play', 'pause', 'seek', 'complete') then 'invalid_event_type'
            when data ->> 'timestamp' is null or data ->> 'timestamp' = '' then 'missing_timestamp'
            when not ((data ->> 'timestamp') ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}') then 'malformed_timestamp'
            when data ->> 'user_id' is null then 'missing_user_id'
            when data ->> 'episode_id' is null then 'missing_episode_id'
            else 'other_issue'
        end as issue_type
    from source
    where data ->> 'event_type' is null 
       or data ->> 'event_type' not in ('play', 'pause', 'seek', 'complete')
       or data ->> 'timestamp' is null 
       or data ->> 'timestamp' = ''
       or not ((data ->> 'timestamp') ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}')
       or data ->> 'user_id' is null
       or data ->> 'episode_id' is null
)

select * from invalid_events 