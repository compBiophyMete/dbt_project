with

-- done activities only (the done filter is applied in int_activities_filtered_to_done)
activities as (

    select
        activity_id,
        deal_id,
        assigned_user_id,
        activity_type_id,
        activity_type,
        activity_type_name,
        due_at
    from
        {{ ref('int_activities_filtered_to_done') }}

),

-- data-quality flag: is the activity's deal in the deal list? exists, so no row is multiplied.
-- Computed here, in the one model that exposes it, so the activity models (and the funnel that
-- reads them) don't depend on int_deals
activities_with_deal_flag as (

    select
        activity_id,
        deal_id,
        assigned_user_id,
        activity_type_id,
        activity_type,
        activity_type_name,
        exists (
            select 1
            from {{ ref('int_deals') }} as deals
            where deals.deal_id = activities.deal_id
        )                                       as has_known_deal,
        due_at
    from
        activities

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
    activities_with_deal_flag
