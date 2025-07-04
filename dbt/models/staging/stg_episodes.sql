-- stg_episodes.sql : clean episode reference data
with source as (
    select * from {{ source('raw', 'episodes') }}
)
select
    cast(episode_id as text) as episode_id,
    cast(podcast_id as text) as podcast_id,
    title,
    cast(release_date as date) as release_date,
    cast(duration_seconds as integer) as duration_seconds
from source; 