-- mart_top_episodes.sql : engagement per episode
with events as (
    select * from {{ ref('stg_user_events') }}
),

plays as (
    select episode_id, count(*) as plays
    from events
    where event_type = 'play'
    group by episode_id
),

completions as (
    select episode_id, count(*) as completions
    from events
    where event_type = 'complete'
    group by episode_id
),

joined as (
    select coalesce(p.episode_id, c.episode_id) as episode_id,
           coalesce(p.plays, 0) as plays,
           coalesce(c.completions, 0) as completions
    from plays p
    full outer join completions c using(episode_id)
)
select
    episode_id,
    plays,
    completions,
    {{ dbt_utils.safe_divide('completions', 'plays') }} as completion_rate
from joined
order by completion_rate desc; 