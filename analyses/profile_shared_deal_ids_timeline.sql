/*
    Question: what does the history of a deal ID with two creations look like?

    Run: dbt show --select profile_shared_deal_ids_timeline --limit 50
    (change the deal_id below to inspect another shared ID: 399956, 554294, 556338, 851850, 955417)

    Result (run 2026-10-21), deal 399956, 17 events:
    | changed_at          | changed_field_key | new_value           | deal |
    |---------------------|-------------------|---------------------|------|
    | 2024-04-06 06:45:44 | add_time          | 2024-04-06T06:45:44 | 1    |
    | 2024-04-08 06:45:44 | user_id           | 594                 | 1    |
    | 2024-04-30 06:45:44 | user_id           | 404                 | 1    |
    | 2024-05-07 06:45:44 | stage_id          | 1                   | 1    |
    | 2024-06-02 06:45:44 | stage_id          | 2                   | 1    |
    | 2024-06-08 06:45:44 | stage_id          | 3                   | 1    |
    | 2024-06-09 06:45:44 | stage_id          | 4                   | 1    |
    | 2024-06-29 18:27:27 | add_time          | 2024-06-29T18:27:27 | 2    |
    | 2024-07-09 06:45:44 | stage_id          | 5                   | 1    |
    | 2024-07-17 06:45:44 | stage_id          | 8                   | 1    |
    | 2024-07-22 18:27:27 | user_id           | 59                  | 2    |
    | 2024-08-01 06:45:44 | lost_reason       | 1                   | 1    |
    | 2024-08-18 18:27:27 | stage_id          | 1                   | 2    |
    | 2024-08-24 18:27:27 | stage_id          | 2                   | 2    |
    | 2024-08-26 18:27:27 | stage_id          | 4                   | 2    |
    | 2024-09-06 18:27:27 | stage_id          | 5                   | 2    |
    | 2024-09-08 18:27:27 | lost_reason       | 1                   | 2    |
    In short: deal 1 (events at 06:45:44) has owners 594 -> 404, stages 1 -> 2 -> 3 -> 4 -> 5 -> 8,
    lost 2024-08-01; deal 2 (events at 18:27:27) has owner 59, stages 1 -> 2 -> 4 -> 5, lost
    2024-09-08. Deal 1 keeps moving (stages 5, 8) and is lost after deal 2 is created.

    Conclusion: two separate deals running in parallel under one ID, not one deal that changed a
    lot. The `deal` column assigns each event by matching its time of day to a creation (see
    profile_shared_deal_ids_time_of_day for why that works in this dataset).

    Relied on by: has_multiple_creations (int_deal_creations_aggregated_to_deals) and the funnel's
    exclusion of shared deal IDs (int_deal_funnel_steps_unioned).
*/

with

changes as (

    select
        deal_id,
        changed_field_key,
        new_value,
        changed_at
    from
        {{ ref('stg_pipedrive__deal_changes') }}
    where
        deal_id = 399956

),

-- the deal's creations, numbered in time order: 1 = first deal, 2 = second deal;
-- new_value (the recorded creation timestamp) breaks a tie on changed_at, so the numbering
-- is the same on every run (the change log has no unique change id to order by)
creations as (

    select
        deal_id,
        changed_at                              as created_at,
        row_number() over (
            partition by deal_id
            order by
                changed_at,
                new_value
        )                                       as deal_number
    from
        changes
    where
        changed_field_key = 'add_time'

)

select
    changes.changed_at,
    changes.changed_field_key,
    changes.new_value,
    creations.deal_number                       as deal
from
    changes
left join creations
    on changes.deal_id = creations.deal_id
    and changes.changed_at::time = creations.created_at::time
order by
    changes.changed_at
