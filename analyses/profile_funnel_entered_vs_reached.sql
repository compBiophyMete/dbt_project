/*
    Question: Per stage, how many deals have a recorded entry into it, and how many reached it
    or a later stage?

    Run: dbt show --select profile_funnel_entered_vs_reached --limit 10

    Result (run 2026-10-17), the 5 shared deal IDs excluded:
    | stage | entered (recorded) | reached (cumulative) | reached only by skipping |
    |-------|--------------------|----------------------|--------------------------|
    | 1     | 1,990              | 1,990                | 0                        |
    | 2     | 1,474              | 1,985                | 511                      |
    | 3     | 1,300              | 1,946                | 646                      |
    | 4     | 1,082              | 1,857                | 775                      |
    | 5     |   892              | 1,688                | 796                      |
    | 6     |   738              | 1,419                | 681                      |
    | 7     |   586              | 1,076                | 490                      |
    | 8     |   476              |   720                | 244                      |
    | 9     |   322              |   322                | 0                        |

    Conclusion: counting only recorded entries (skipped stages not counted) would drop up to 796 deals per
    stage that passed it by skipping, and make stage 1 → 2 look like a 26% drop-off (1,990 →
    1,474) when only 5 deals stopped there (1,990 → 1,985). The cumulative counts never rise
    from one stage to the next.

    Relied on by: the cumulative stage rule; the stage steps of
    int_deal_funnel_steps_unioned, fct_deal_funnel_steps and rep_sales_funnel_monthly.
*/

with

shared_deal_ids as (

    select
        deal_id
    from
        {{ ref('int_deal_creations_aggregated_to_deals') }}
    where
        has_multiple_creations

),

-- recorded entries: one row per deal and stage it entered (first entry)
entered as (

    select
        stage_id,
        count(*)                                as deals_entered_recorded
    from
        {{ ref('int_deal_stage_changes_aggregated_to_entries') }}
    where
        deal_id not in (select deal_id from shared_deal_ids)
    group by
        stage_id

),

-- reached: the funnel's stage steps (cumulative rule, shared deal IDs excluded)
reached as (

    select
        funnel_steps.stage_id,
        count(*)                                as deals_reached_cumulative
    from
        {{ ref('int_deal_funnel_steps_unioned') }} as funnel_events
    inner join {{ ref('int_funnel_steps_mapped') }} as funnel_steps
        on funnel_events.funnel_step = funnel_steps.funnel_step
    where
        funnel_steps.stage_id is not null
    group by
        funnel_steps.stage_id

)

select
    entered.stage_id,
    entered.deals_entered_recorded,
    reached.deals_reached_cumulative,
    reached.deals_reached_cumulative - entered.deals_entered_recorded as reached_only_by_skipping
from
    entered
inner join reached
    on entered.stage_id = reached.stage_id
order by
    entered.stage_id
