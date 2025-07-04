-- stg_user_events.sql : typed raw event records from JSONB
with source as (
    select data
    from {{ source('raw', 'event_files') }}
),

filtered as (
    select * from source
    where data ->> 'type' in ('play', 'pause', 'seek', 'complete')
),

typed as (
    select
        {{ dbt_utils.generate_surrogate_key([
            "data ->> 'user_id'",
            "data ->> 'episode_id'",
            "data ->> 'ts'",
            "data ->> 'type'"
        ]) }} as event_id,
        data ->> 'user_id'      as user_id,
        data ->> 'episode_id'   as episode_id,
        (data ->> 'ts')::timestamp as event_ts,
        data ->> 'type'         as event_type,
        (data ->> 'duration')::integer as duration
    from filtered
)
select * from typed; 