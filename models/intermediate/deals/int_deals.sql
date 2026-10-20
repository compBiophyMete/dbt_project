with

-- the deal list: every deal with any history in the change log (creation, stage, owner or loss)
deal_changes as (

    select distinct
        deal_id
    from
        {{ ref('stg_pipedrive__deal_changes') }}

),

-- one row per deal with a creation; the shared-ID flag is defined there
creations_per_deal as (

    select
        deal_id,
        has_multiple_creations,
        created_at
    from
        {{ ref('int_deal_creations_aggregated_to_deals') }}

),

owner_changes as (

    select
        deal_id,
        owner_user_id,
        changed_at
    from
        {{ ref('int_deal_changes_filtered_to_owners') }}

),

stage_changes as (

    select
        deal_id,
        stage_id,
        changed_at
    from
        {{ ref('int_deal_changes_filtered_to_stages') }}

),

losses as (

    select
        deal_id,
        lost_reason_id,
        stage_id_at_loss,
        changed_at
    from
        {{ ref('int_deal_losses_joined_to_stages') }}

),

-- owner rows ranked both ways per deal. (deal_id, changed_at) is unique, so there are no ties
owner_changes_ranked as (

    select
        deal_id,
        owner_user_id,
        row_number() over (
            partition by deal_id
            order by changed_at asc
        )                                       as first_rank,
        row_number() over (
            partition by deal_id
            order by changed_at desc
        )                                       as last_rank
    from
        owner_changes

),

-- the first recorded owner, not the owner at creation: no owner row in this data shares a
-- creation time (an owner from creation is reported on Pipedrive's forum, see int_deals.yml)
owners_per_deal as (

    select
        deal_id,
        max(owner_user_id) filter (where first_rank = 1) as first_recorded_owner_user_id,
        max(owner_user_id) filter (where last_rank = 1)  as current_owner_user_id,
        count(*) - 1                            as owner_change_count
    from
        owner_changes_ranked
    group by
        deal_id

),

-- latest stage change first; (deal_id, changed_at) is unique, so there are no ties
stage_changes_ranked as (

    select
        deal_id,
        stage_id,
        changed_at,
        row_number() over (
            partition by deal_id
            order by changed_at desc
        )                                       as last_rank
    from
        stage_changes

),

stages_per_deal as (

    select
        deal_id,
        max(stage_id) filter (where last_rank = 1)   as current_stage_id,
        max(stage_id)                                as furthest_stage_id,
        count(*)                                     as stage_change_count,
        max(changed_at) filter (where last_rank = 1) as current_stage_entered_at
    from
        stage_changes_ranked
    group by
        deal_id

),

-- the deal's latest loss: a lost deal can be reopened and lost again, and a lost reason can be
-- edited; both add a row, and the latest one is the deal's current loss
losses_ranked as (

    select
        deal_id,
        lost_reason_id,
        stage_id_at_loss,
        changed_at,
        row_number() over (
            partition by deal_id
            order by changed_at desc
        )                                       as last_rank
    from
        losses

),

latest_losses as (

    select
        deal_id,
        lost_reason_id,
        stage_id_at_loss,
        changed_at                              as lost_at
    from
        losses_ranked
    where
        last_rank = 1

),

-- every rollup has one row per deal (1:1), so every deal keeps exactly one row
deals as (

    select
        deal_changes.deal_id,
        owners_per_deal.first_recorded_owner_user_id,
        owners_per_deal.current_owner_user_id,
        stages_per_deal.current_stage_id,
        stages_per_deal.furthest_stage_id,
        latest_losses.lost_reason_id,
        latest_losses.stage_id_at_loss,
        coalesce(owners_per_deal.owner_change_count, 0)    as owner_change_count,
        coalesce(stages_per_deal.stage_change_count, 0)    as stage_change_count,
        coalesce(creations_per_deal.has_multiple_creations, false) as has_multiple_creations,
        creations_per_deal.created_at,
        stages_per_deal.current_stage_entered_at,
        latest_losses.lost_at
    from
        deal_changes
    left join creations_per_deal
        on deal_changes.deal_id = creations_per_deal.deal_id
    left join owners_per_deal
        on deal_changes.deal_id = owners_per_deal.deal_id
    left join stages_per_deal
        on deal_changes.deal_id = stages_per_deal.deal_id
    left join latest_losses
        on deal_changes.deal_id = latest_losses.deal_id

)

select
    deal_id,
    first_recorded_owner_user_id,
    current_owner_user_id,
    current_stage_id,
    furthest_stage_id,
    lost_reason_id,
    stage_id_at_loss,
    owner_change_count,
    stage_change_count,
    has_multiple_creations,
    created_at,
    current_stage_entered_at,
    lost_at
from
    deals
