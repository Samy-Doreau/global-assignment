{{ config(materialized='table') }}
-- fact_user_events.sql : central fact table of cleaned user events
select * from {{ ref('stg_user_events') }} 