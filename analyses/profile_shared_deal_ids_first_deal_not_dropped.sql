/*
    Question: on a deal ID with two creations, was the first deal dropped when the second was
    created? If so, the latest creation time would be the right `created_at` for the ID.

    Run: dbt show --select profile_shared_deal_ids_first_deal_not_dropped

    Result (run 2026-10-18), one row per shared ID:

    | deal_id | second created | first deal's events after it | first deal lost | second deal lost |
    |---------|----------------|------------------------------|-----------------|------------------|
    | 399956  | 2024-06-29     | 3                            | 2024-08-01      | 2024-09-08       |
    | 554294  | 2024-08-13     | 4                            | 2024-10-08      | 2024-11-08       |
    | 556338  | 2024-09-06     | 3                            | 2024-11-02      | 2024-12-29       |
    | 851850  | 2024-06-09     | 1                            | 2024-06-10      | 2024-10-15       |
    | 955417  | 2024-08-22     | 5                            | 2024-10-28      | 2024-11-24       |

    Conclusion: in all 5 the first deal keeps moving and is lost AFTER the second creation, so it
    was not dropped. The latest creation time would put the first deal's events before its own
    creation; int_deals keeps the earliest (decision 2026-10-18). Events are assigned to a deal by
    time of day (see profile_shared_deal_ids_time_of_day).

    Relied on by: created_at = the earliest creation (int_deals.created_at); the rejected "latest
    creation" alternative documented in int_deals.
*/

with

changes as (

    select
        deal_id,
        changed_field_key,
        changed_at
    from
        {{ ref('stg_pipedrive__deal_changes') }}
    where
        deal_id in (
            select deal_id
            from {{ ref('int_deal_creations_aggregated_to_deals') }}
            where has_multiple_creations
        )

),

-- the creations of each shared ID, numbered in time order: 1 = first deal, 2 = second deal
creations as (

    select
        deal_id,
        changed_at                              as created_at,
        row_number() over (
            partition by deal_id
            order by changed_at
        )                                       as deal_number
    from
        changes
    where
        changed_field_key = 'add_time'

),

-- every event assigned to the deal whose creation shares its time of day
events as (

    select
        changes.deal_id,
        changes.changed_field_key,
        changes.changed_at,
        creations.deal_number
    from
        changes
    left join creations
        on changes.deal_id = creations.deal_id
        and changes.changed_at::time = creations.created_at::time

),

second_creations as (

    select
        deal_id,
        created_at                              as second_created_at
    from
        creations
    where
        deal_number = 2

)

select
    events.deal_id,
    second_creations.second_created_at,
    count(*) filter (
        where events.deal_number = 1
            and events.changed_at > second_creations.second_created_at
    )                                           as first_deal_events_after_second_creation,
    max(events.changed_at) filter (
        where events.deal_number = 1
            and events.changed_field_key = 'lost_reason'
    )                                           as first_deal_lost_at,
    max(events.changed_at) filter (
        where events.deal_number = 2
            and events.changed_field_key = 'lost_reason'
    )                                           as second_deal_lost_at
from
    events
inner join second_creations
    on events.deal_id = second_creations.deal_id
group by
    events.deal_id,
    second_creations.second_created_at
order by
    events.deal_id
