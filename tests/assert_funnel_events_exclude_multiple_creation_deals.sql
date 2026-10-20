/*
    Deals with more than one creation (reused deal IDs holding two lifecycles) are excluded
    from the funnel. Returns every funnel event of such a deal; any row fails the test.
*/

select
    funnel_events.deal_id,
    funnel_events.funnel_step
from
    {{ ref('int_deal_funnel_steps_unioned') }} as funnel_events
where
    funnel_events.deal_id in (
        select deal_id
        from {{ ref('int_deal_creations_aggregated_to_deals') }}
        where has_multiple_creations
    )
