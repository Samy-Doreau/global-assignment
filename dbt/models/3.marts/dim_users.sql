-- dim_users.sql : dimension table for users (one row per user)
select 
    user_id as "User ID",
    signup_date as "Signup Date",
    country as "Country"
from {{ ref('stg_users') }} 