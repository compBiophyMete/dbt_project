with

-- stage changes, one row per deal and change (deal_id, changed_at)
stage_changes as (

    select
        deal_id,
        stage_id,
        changed_at
    from
        {{ ref('int_deal_changes_filtered_to_stages') }}

),

stages as (

    select
        stage_id,
        stage_name
    from
        {{ ref('stg_pipedrive__stages') }}

),

-- the stage name is joined here, at build time, so every row shows the current name; the append
-- table upstream stores only stage_id. stage_id is unique in stg_pipedrive__stages (n:1), so the join never
-- changes the row count
enriched as (

    select
        stage_changes.deal_id,
        stage_changes.stage_id,
        stages.stage_name,
        stage_changes.changed_at
    from
        stage_changes
    left join stages
        on stage_changes.stage_id = stages.stage_id

)

select
    deal_id,
    stage_id,
    stage_name::varchar(255)                    as stage_name,
    changed_at
from
    enriched
