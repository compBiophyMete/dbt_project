with

creations as (

    select
        deal_id,
        created_at
    from
        {{ ref('int_deal_changes_filtered_to_creations') }}

),

-- one row per deal. A deal ID with more than one creation holds two separate deals that ran in
-- parallel (an ID collision); the flag lets each consumer decide (the funnel excludes them)
creations_per_deal as (

    select
        deal_id,
        count(*) > 1                            as has_multiple_creations,
        -- earliest, not latest: the first deal on a shared ID was not dropped (it was lost after
        -- the second creation), so only the earliest precedes every event on the ID
        min(created_at)                         as created_at
    from
        creations
    group by
        deal_id

)

select
    deal_id,
    has_multiple_creations,
    created_at
from
    creations_per_deal
