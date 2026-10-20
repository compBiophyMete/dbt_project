with

stage_changes as (

    select
        deal_id,
        stage_id,
        changed_at
    from
        {{ ref('int_deal_changes_filtered_to_stages') }}

),

-- only stages recorded in the change log count, so a skipped stage gets no row.
-- a stage counts once per deal, at its first entry (min), so re-entries collapse
stage_entries as (

    select
        deal_id,
        stage_id,
        min(changed_at)                         as entered_at
    from
        stage_changes
    group by
        deal_id,
        stage_id

)

select
    deal_id,
    stage_id,
    entered_at
from
    stage_entries
