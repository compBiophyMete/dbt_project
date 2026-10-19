with

source as (

    select
        {{ dbt_utils.star(from=source('pipedrive', 'users')) }}
    from
        {{ source('pipedrive', 'users') }}

),

renamed as (

    select
        id                                      as user_id,
        nullif(trim(name), '')                  as user_name,
        nullif(trim(email), '')                 as email,
        modified                                as modified_at
    from
        source

)

select
    user_id,
    user_name,
    email,
    -- <letters/digits…>@<domain>.<tld>, case-insensitive (~*): email keeps its case; a null email is not a valid one
    coalesce(email ~* '^[a-z0-9][a-z0-9._%+-]*@[a-z0-9.-]+\.[a-z]+$', false) as is_valid_email,
    modified_at
from
    renamed
