with

activity_types as (

    select
        activity_type_id,
        activity_type,
        activity_type_name,
        is_activity_type_active
    from
        {{ ref('stg_pipedrive__activity_types') }}

)

select
    activity_type_id,
    activity_type::varchar(50)                  as activity_type,
    activity_type_name::varchar(255)            as activity_type_name,
    is_activity_type_active
from
    activity_types
