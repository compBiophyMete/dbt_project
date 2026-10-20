with

-- losses with the stage at loss already applied (business rule in int_deal_losses_joined_to_stages)
losses as (

    select
        deal_id,
        lost_reason_id,
        stage_id_at_loss,
        changed_at                              as lost_at
    from
        {{ ref('int_deal_losses_joined_to_stages') }}

),

-- names from the conformed dimensions, so every mart shows the same name for a key
lost_reasons as (

    select
        lost_reason_id,
        lost_reason_name
    from
        {{ ref('dim_lost_reasons') }}

),

stages as (

    select
        stage_id,
        stage_name
    from
        {{ ref('dim_stages') }}

),

-- names are joined here, at build time, so every row shows the current lost-reason and stage name;
-- the append tables upstream store only the IDs. Both lookups are unique on their key (n:1), so
-- the joins never change the row count
enriched as (

    select
        losses.deal_id,
        losses.lost_reason_id,
        lost_reasons.lost_reason_name,
        losses.stage_id_at_loss,
        stages_at_loss.stage_name               as stage_name_at_loss,
        losses.lost_at
    from
        losses
    left join lost_reasons
        on losses.lost_reason_id = lost_reasons.lost_reason_id
    left join stages as stages_at_loss
        on losses.stage_id_at_loss = stages_at_loss.stage_id

)

select
    deal_id,
    lost_reason_id,
    lost_reason_name::varchar(255)             as lost_reason_name,
    stage_id_at_loss,
    stage_name_at_loss::varchar(255)            as stage_name_at_loss,
    lost_at
from
    enriched
