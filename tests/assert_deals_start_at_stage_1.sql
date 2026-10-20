{{ config(severity='warn') }}

/*
    Early warning about the recorded stages: every deal with a stage history has a recorded entry
    into stage 1 (last known result: analyses/profile_deals_first_stage.sql). Returns each deal that has
    stage entries but no recorded entry into stage 1, i.e. it started directly at a later stage.

    "Recorded entry into stage 1" (checked here, in int_deal_stage_changes_aggregated_to_entries) is not the same as
    "reached funnel step 1" (int_deal_funnel_steps_unioned): under the cumulative rule, any stage entry
    reaches step 1. So such a deal still counts in Lead Generation, dated by its first stage entry,
    and stays in the report; nothing breaks, hence a warning, not an error.
    But its funnel dates would then hide that it skipped the start of the funnel, so it is worth a
    look when it first appears.
*/

select
    deal_id,
    min(stage_id)                               as first_stage_id,
    min(entered_at)                             as first_entered_at
from
    {{ ref('int_deal_stage_changes_aggregated_to_entries') }}
group by
    deal_id
having
    count(*) filter (where stage_id = 1) = 0
