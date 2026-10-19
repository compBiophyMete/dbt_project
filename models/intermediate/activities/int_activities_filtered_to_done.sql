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

),

-- data-quality flag: is the activity's deal one of our deals? checked against the deal list
-- (int_deals, one row per deal) with exists, so no join can multiply the activity
activity_with_deal_flag as (

    select
        activity_id,
        deal_id,
        assigned_user_id,
        activity_type_id,
        activity_type,
        activity_type_name,
        is_activity_type_active,
        exists (
            select 1
            from {{ ref('int_deals') }} as deals
            where deals.deal_id = activity_with_types.deal_id
        )                                       as has_known_deal,
        due_at
    from
        activity_with_types

)

select
    activity_id,
    deal_id,
    assigned_user_id,
    activity_type_id,
    activity_type,
    activity_type_name,
    is_activity_type_active,
    has_known_deal,
    due_at
from
    activity_with_deal_flag
