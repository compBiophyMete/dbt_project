with

-- one row per deal and funnel step reached; every funnel rule (cumulative stages, done calls, shared deal IDs excluded)
-- is applied in int_deal_funnel_steps_unioned
funnel_events as (

    select
        deal_id,
        funnel_step,
        entered_at
    from
        {{ ref('int_deal_funnel_steps_unioned') }}

)

select
    deal_id,
    funnel_step::varchar(10)                    as funnel_step,
    entered_at
from
    funnel_events
