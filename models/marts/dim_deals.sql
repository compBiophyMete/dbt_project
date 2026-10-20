with

-- one row per deal with its attributes; all deal-level rules are applied in int_deals
deals as (

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
        {{ ref('int_deals') }}

),

-- labels from the conformed dimensions, so each name has one source; all three are unique on
-- their key (n:1), so the joins never change the row count
stages as (

    select
        stage_id,
        stage_name
    from
        {{ ref('dim_stages') }}

),

users as (

    select
        user_id,
        user_name
    from
        {{ ref('dim_users') }}

),

lost_reasons as (

    select
        lost_reason_id,
        lost_reason_name
    from
        {{ ref('dim_lost_reasons') }}

),

-- wide (star, not snowflake): every key gets its current label, joined at build time
enriched as (

    select
        deals.deal_id,
        deals.first_recorded_owner_user_id,
        deals.current_owner_user_id,
        deals.current_stage_id,
        deals.furthest_stage_id,
        deals.lost_reason_id,
        deals.stage_id_at_loss,
        first_recorded_owners.user_name         as first_recorded_owner_name,
        current_owners.user_name                as current_owner_name,
        current_stages.stage_name               as current_stage_name,
        furthest_stages.stage_name              as furthest_stage_name,
        lost_reasons.lost_reason_name,
        stages_at_loss.stage_name               as stage_name_at_loss,
        deals.owner_change_count,
        deals.stage_change_count,
        deals.has_multiple_creations,
        deals.created_at,
        deals.current_stage_entered_at,
        deals.lost_at
    from
        deals
    left join users as first_recorded_owners
        on deals.first_recorded_owner_user_id = first_recorded_owners.user_id
    left join users as current_owners
        on deals.current_owner_user_id = current_owners.user_id
    left join stages as current_stages
        on deals.current_stage_id = current_stages.stage_id
    left join stages as furthest_stages
        on deals.furthest_stage_id = furthest_stages.stage_id
    left join stages as stages_at_loss
        on deals.stage_id_at_loss = stages_at_loss.stage_id
    left join lost_reasons
        on deals.lost_reason_id = lost_reasons.lost_reason_id

)

select
    deal_id,
    first_recorded_owner_user_id,
    current_owner_user_id,
    current_stage_id,
    furthest_stage_id,
    lost_reason_id,
    stage_id_at_loss,
    first_recorded_owner_name,
    current_owner_name,
    current_stage_name,
    furthest_stage_name,
    lost_reason_name,
    stage_name_at_loss,
    -- counts are bigint (count(*)) upstream; integer is the contract type
    owner_change_count::integer                 as owner_change_count,
    stage_change_count::integer                 as stage_change_count,
    has_multiple_creations,
    created_at,
    current_stage_entered_at,
    lost_at
from
    enriched
