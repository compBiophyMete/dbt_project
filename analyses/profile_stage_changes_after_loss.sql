/*
    Question: Does any deal enter another stage after it was lost?

    Run: dbt show --select profile_stage_changes_after_loss --limit 5

    Result (run 2026-10-20):
    | shared ID | lost deals | lost more than once | deals with a stage change after the first loss | stage changes after the first loss |
    |-----------|------------|---------------------|------------------------------------------------|------------------------------------|
    | false     | 1,990      | 0                   | 0                                              | 0                                  |
    | true      | 5          | 5                   | 4                                              | 13                                 |

    Conclusion: for normal deals a loss is the last stage event: each is lost once and no stage
    change follows it, so no lost deal re-enters the pipeline. On the shared deal IDs the stage
    changes after the first loss belong to the other deal on the same ID (see
    profile_shared_deal_ids_timeline), not to a reopened deal.

    Relied on by: the "losses don't remove a deal from a step" rule in int_deal_funnel_steps_unioned
    and rep_sales_funnel_monthly; the funnel's exclusion of shared deal IDs.
*/

with

-- each deal's first loss, and how many losses it has
losses as (

    select
        deal_id,
        min(changed_at)                         as first_lost_at,
        count(*)                                as loss_count
    from
        {{ ref('int_deal_changes_filtered_to_losses') }}
    group by
        deal_id

),

shared_id_flags as (

    select
        deal_id,
        has_multiple_creations
    from
        {{ ref('int_deal_creations_aggregated_to_deals') }}

),

-- stage changes recorded after the deal's first loss
stage_changes_after_loss as (

    select
        stage_changes.deal_id,
        count(*)                                as stage_changes_after_first_loss
    from
        {{ ref('int_deal_changes_filtered_to_stages') }} as stage_changes
    inner join losses
        on stage_changes.deal_id = losses.deal_id
    where
        stage_changes.changed_at > losses.first_lost_at
    group by
        stage_changes.deal_id

)

select
    coalesce(shared_id_flags.has_multiple_creations, false) as is_shared_id,
    count(*)                                    as lost_deals,
    count(*) filter (where losses.loss_count > 1) as deals_lost_more_than_once,
    count(stage_changes_after_loss.deal_id)     as deals_with_stage_change_after_loss,
    coalesce(sum(stage_changes_after_loss.stage_changes_after_first_loss), 0) as stage_changes_after_loss
from
    losses
left join shared_id_flags
    on losses.deal_id = shared_id_flags.deal_id
left join stage_changes_after_loss
    on losses.deal_id = stage_changes_after_loss.deal_id
group by
    coalesce(shared_id_flags.has_multiple_creations, false)
order by
    is_shared_id
