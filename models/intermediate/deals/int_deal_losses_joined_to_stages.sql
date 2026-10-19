with

losses as (

    select
        deal_id,
        lost_reason_id,
        changed_at
    from
        {{ ref('int_deal_changes_filtered_to_losses') }}

),

stage_changes as (

    select
        deal_id,
        stage_id,
        changed_at
    from
        {{ ref('int_deal_changes_filtered_to_stages') }}

),

-- every stage change of the deal at or before the loss, ranked latest first per loss.
-- left join: a loss with no earlier stage change keeps one row, with a null stage.
-- (deal_id, changed_at) is unique in stage_changes, so the ranking has no ties
stage_changes_before_loss as (

    select
        losses.deal_id,
        losses.lost_reason_id,
        stage_changes.stage_id,
        losses.changed_at,
        row_number() over (
            partition by
                losses.deal_id,
                losses.changed_at
            order by
                stage_changes.changed_at desc
        )                                       as stage_rank
    from
        losses
    left join stage_changes
        on losses.deal_id = stage_changes.deal_id
        and stage_changes.changed_at <= losses.changed_at

),

-- business rule: the stage at loss is the deal's latest stage change at or before the loss
losses_with_stage as (

    select
        deal_id,
        lost_reason_id,
        stage_id                                as stage_id_at_loss,
        changed_at
    from
        stage_changes_before_loss
    where
        stage_rank = 1

)

select
    deal_id,
    lost_reason_id,
    stage_id_at_loss,
    changed_at
from
    losses_with_stage
