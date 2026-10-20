/*
    Question: How do deals move between stages: to the next stage, skipping stages, or backwards?

    Run: dbt show --select profile_stage_skips --limit 60

    Result (run 2026-10-17), 6,911 moves (8,906 stage changes minus 1,995 first entries):
    - next stage: 4,399 moves (e.g. 1 → 2: 1,481; 2 → 3: 978; 3 → 4: 701);
    - skip forward: 2,502 moves (e.g. 1 → 3: 329; 3 → 5: 282; 2 → 4: 274; 4 → 6: 222);
    - backward or repeat: 10 moves (e.g. 8 → 1, 3 → 2, 9 → 9).
    A companion check (`select count(*) … where to_stage_id <= from_stage_id`, run the same day)
    found all 10 backward or repeat moves on the 5 shared deal IDs.

    Conclusion: skipping stages is normal: more than a third of all moves (2,502 of 6,911) jump
    forward past at least one stage. Backward moves don't happen in normal deals; the 10 that
    exist belong to the IDs holding two deals. So "entered a stage" (recorded) and "reached a
    stage" (got at least that far) differ a lot (see profile_funnel_entered_vs_reached).

    Relied on by: the cumulative stage rule (int_deal_funnel_steps_unioned); first entry only
    (int_deal_stage_changes_aggregated_to_entries); furthest_stage_id >= current_stage_id test on int_deals (except shared IDs).
*/

with

-- each stage change with the stage the deal came from
moves as (

    select
        deal_id,
        lag(stage_id) over (
            partition by deal_id
            order by changed_at
        )                                       as from_stage_id,
        stage_id                                as to_stage_id
    from
        {{ ref('int_deal_changes_filtered_to_stages') }}

)

select
    from_stage_id,
    to_stage_id,
    count(*)                                    as moves,
    case
        when to_stage_id > from_stage_id + 1 then 'skip forward'
        when to_stage_id = from_stage_id + 1 then 'next stage'
        else 'backward or repeat'
    end                                         as move_type
from
    moves
where
    from_stage_id is not null
group by
    from_stage_id,
    to_stage_id
order by
    from_stage_id,
    to_stage_id
