with

-- every stage entry of every deal: reaching a step depends on later stages too (cumulative rule).
-- int_deal_stage_changes_aggregated_to_entries holds one row per deal and stage, at its first entry
stage_entries as (

    select
        deal_id,
        stage_id,
        entered_at
    from
        {{ ref('int_deal_stage_changes_aggregated_to_entries') }}

),

-- done activities; the done filter is applied in int_activities_filtered_to_done. Which types are funnel
-- steps is decided by int_funnel_steps_mapped (inner join in call_steps)
done_activities as (

    select
        deal_id,
        activity_type,
        due_at
    from
        {{ ref('int_activities_filtered_to_done') }}

),

-- the funnel steps and what each is made of: the one place where stages and activity types are
-- mapped to steps
funnel_steps as (

    select
        funnel_step,
        stage_id,
        activity_type
    from
        {{ ref('int_funnel_steps_mapped') }}

),

-- shared-ID flag, one row per deal: a deal ID with more than one creation holds two separate deals (an
-- ID collision); they can't be split reliably, so the funnel excludes them. The flag is defined
-- once, in int_deal_creations_aggregated_to_deals
deals as (

    select
        deal_id,
        has_multiple_creations
    from
        {{ ref('int_deal_creations_aggregated_to_deals') }}

),

-- A deal reaches a stage step at its first entry into
-- that stage or any later one, so a deal that skipped the stage (1 -> 3) still counts. The range
-- join pairs each stage step with the deal's entries into that stage or beyond; min() keeps the
-- first
stage_steps as (

    select
        stage_entries.deal_id,
        funnel_steps.funnel_step,
        min(stage_entries.entered_at)           as entered_at
    from
        funnel_steps
    inner join stage_entries
        on stage_entries.stage_id >= funnel_steps.stage_id
    group by
        stage_entries.deal_id,
        funnel_steps.funnel_step

),

-- call steps: the inner join keeps only activity types that are funnel steps. Every deal with
-- a done call counts, known to the pipeline or not. Dated by due_at, the only activity date.
-- A deal counts once per step, at its first done call (min), like a stage at its first entry
call_steps as (

    select
        done_activities.deal_id,
        funnel_steps.funnel_step,
        min(done_activities.due_at)             as entered_at
    from
        funnel_steps
    inner join done_activities
        on done_activities.activity_type = funnel_steps.activity_type
    group by
        done_activities.deal_id,
        funnel_steps.funnel_step

),

-- every funnel step at one grain (deal × step). union all: stage steps and call steps can't
-- share a funnel_step, so there is nothing to deduplicate
funnel_events as (

    select
        deal_id,
        funnel_step,
        entered_at
    from
        stage_steps

    union all

    select
        deal_id,
        funnel_step,
        entered_at
    from
        call_steps

),

-- the flag has one row per deal (n:1), so the join can't
-- multiply rows; call deals mostly have no creation row, so coalesce keeps them
funnel_events_without_shared_ids as (

    select
        funnel_events.deal_id,
        funnel_events.funnel_step,
        funnel_events.entered_at
    from
        funnel_events
    left join deals
        on funnel_events.deal_id = deals.deal_id
    where
        not coalesce(deals.has_multiple_creations, false)

)

select
    deal_id,
    funnel_step,
    entered_at
from
    funnel_events_without_shared_ids
