-- stg_users.sql : clean user reference data
with source as (
    select * from {{ source('raw', 'users') }}
)
select
    cast(user_id as integer) as user_id,
    user_name,
    user_email
from source; 