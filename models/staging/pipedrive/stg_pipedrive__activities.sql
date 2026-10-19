with

source as (

    select
        {{ dbt_utils.star(from=source('postgres_public', 'activity')) }}
    from
        {{ source('postgres_public', 'activity') }}

),

renamed as (

    select
        activity_id,
        deal_id,
        assigned_to_user                        as assigned_user_id,
        lower(nullif(trim(type), ''))           as activity_type,
        coalesce(done, false)                   as is_done,
        due_to                                  as due_at
    from
        source

)

select
    activity_id,
    deal_id,
    assigned_user_id,
    activity_type,
    is_done,
    due_at
from
    renamed
