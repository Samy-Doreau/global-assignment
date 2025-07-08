-- mart_top_episodes.sql : engagement per episode
with events as (
    select * from {{ ref('stg_user_events') }}
),

-- Get users who played each episode
episode_plays as (
    select distinct episode_id, user_id
    from events
    where event_type = 'play'
),

-- Get users who completed each episode
episode_completions as (
    select distinct episode_id, user_id
    from events
    where event_type = 'complete'
),

-- Join to ensure we only count completions from users who played
episode_engagement as (
    select 
        ep.episode_id,
        ep.user_id,
        case when ec.user_id is not null then 1 else 0 end as completed
    from episode_plays ep
    left join episode_completions ec 
        on ep.episode_id = ec.episode_id 
        and ep.user_id = ec.user_id
),

-- Aggregate to episode level
episode_metrics as (
    select
        episode_id,
        count(*) as unique_plays,
        sum(completed) as unique_completions
    from episode_engagement
    group by episode_id
)

select
    episode_id,
    unique_plays,
    unique_completions,
    case 
        when unique_plays = 0 then null
        else round((unique_completions::float / unique_plays::float)::numeric, 3)
    end as completion_rate
from episode_metrics
order by completion_rate desc