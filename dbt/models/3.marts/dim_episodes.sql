-- dim_episodes.sql : dimension table for episodes (one row per episode)
select 
    episode_id as "Episode ID",
    podcast_id as "Podcast ID",
    title as "Title",
    release_date as "Release Date",
    duration_seconds as "Duration (seconds)"
from {{ ref('stg_episodes') }} 