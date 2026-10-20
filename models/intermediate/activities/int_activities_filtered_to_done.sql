with

-- only the done activities: is_done is the only per-activity column that says an activity
-- happened.
activity_with_types as (

    select
        activity_id,
        deal_id,
        assigned_user_id,
        activity_type_id,
        activity_type,
        activity_type_name,
        is_activity_type_active,
        due_at
    from {{ ref('int_activities_joined_to_types') }}
    where
        is_done

)

select
    activity_id,
    deal_id,
    assigned_user_id,
    activity_type_id,
    activity_type,
    activity_type_name,
    is_activity_type_active,
    due_at
from
    activity_with_types
