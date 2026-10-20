/*
    Question: Which stage does every deal enter first?

    Run: dbt show --select profile_deals_first_stage --limit 10

    Result (run 2026-10-21):
    | first stage | deals | total deals |
    |-------------|-------|-------------|
    | 1           | 1,995 | 1,995       |

    Conclusion: every deal in the change log (1,995 of 1,995, shared IDs included) has a stage
    change, and each one enters stage 1, Lead Generation, first; no deal starts at a later stage.

    Relied on by: step 1 Lead Generation = stage 1 entry (int_deal_funnel_steps_unioned); the warning
    test assert_deals_start_at_stage_1.
*/

with

-- each deal's stage changes, earliest first
stage_changes_ranked as (

    select
        deal_id,
        stage_id,
        row_number() over (
            partition by deal_id
            order by changed_at
        )                                       as stage_rank
    from
        {{ ref('int_deal_changes_filtered_to_stages') }}

)

select
    stage_id                                    as first_stage_id,
    count(*)                                    as deals,
    -- the deal list (int_deals, one row per deal in the change log): a deal without a stage change
    -- shows up as a gap between deals and total_deals
    (select count(*) from {{ ref('int_deals') }}) as total_deals
from
    stage_changes_ranked
where
    stage_rank = 1
group by
    stage_id
order by
    stage_id
