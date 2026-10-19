with

-- done activities only (the done filter is applied in int_activities_filtered_to_done), with the has_known_deal flag
activities as (

    select
        activity_id,
        deal_id,
        assigned_user_id,
        activity_type_id,
        activity_type,
        activity_type_name,
        has_known_deal,
        due_at
    from
        {{ ref('int_activities_filtered_to_done') }}

)

select
    activity_id,
    deal_id,
    assigned_user_id,
    activity_type_id,
    activity_type::varchar(50)                  as activity_type,
    activity_type_name::varchar(255)            as activity_type_name,
    has_known_deal,
    due_at
from
    activities
