-- stg_users.sql : clean user reference data
with source as (
    select * from {{ source('raw', 'users') }}
)
select
    cast(user_id as text) as user_id,
    cast(signup_date as date) as signup_date,
    country
from source; 