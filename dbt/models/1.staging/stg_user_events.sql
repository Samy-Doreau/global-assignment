-- stg_user_events.sql : typed raw event records
with source as (
    select * from {{ source('raw', 'events') }}
),

filtered as (
    select *
    from source
    where type in ('play', 'pause', 'seek', 'complete')
),

typed as (
    select
        {{ dbt_utils.generate_surrogate_key(['user_id', 'episode_id', 'ts', 'type']) }} as event_id,
        cast(user_id as integer)        as user_id,
        cast(episode_id as integer)     as episode_id,
        cast(ts as timestamp)           as event_ts,
        cast(type as string)            as event_type,
        cast(duration as integer)       as duration
    from filtered
)

select * from typed; 