-- stg_episodes.sql : clean episode reference data
with source as (
    select * from {{ source('raw', 'episodes') }}
)
select
    cast(episode_id as integer) as episode_id,
    title,
    show_name
from source; 