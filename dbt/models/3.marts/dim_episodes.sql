-- dim_episodes.sql : dimension table for episodes (one row per episode)
select * from {{ ref('stg_episodes') }} 