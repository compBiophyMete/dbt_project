with

activity as (

    select
        activity_id,
        deal_id,
        assigned_user_id,
        activity_type,
        is_done,
        due_at
    from {{ ref('stg_pipedrive__activities') }}

),

activity_types as (

    select
        activity_type_id,
        activity_type,
        activity_type_name,
        is_activity_type_active
    from {{ ref('stg_pipedrive__activity_types') }}

),

-- lookup: activity_type is unique in stg_pipedrive__activity_types, so the join never changes the row count
enriched as (

    select
        activity.activity_id,
        activity.deal_id,
        activity.assigned_user_id,
        activity_types.activity_type_id,
        activity.activity_type,
        activity_types.activity_type_name,
        activity.is_done,
        activity_types.is_activity_type_active,
        activity.due_at
    from activity
    left join activity_types
        on activity.activity_type = activity_types.activity_type

)

select
    activity_id,
    deal_id,
    assigned_user_id,
    activity_type_id,
    activity_type,
    activity_type_name,
    is_done,
    is_activity_type_active,
    due_at
from enriched
