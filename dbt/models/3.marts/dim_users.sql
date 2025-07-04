-- dim_users.sql : dimension table for users (one row per user)
select * from {{ ref('stg_users') }} 