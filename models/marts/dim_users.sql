with

-- no email: personal data stays out of the public layer until a consumer needs it
users as (

    select
        user_id,
        user_name,
        is_valid_email,
        modified_at,
        dwh_date
    from
        {{ ref('int_users') }}

)

select
    user_id,
    user_name::varchar(255)                     as user_name,
    is_valid_email,
    modified_at
from
    users
