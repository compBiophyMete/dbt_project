/*
    Question: does every event happen at the same time of day as its deal's creation? If yes, the
    events of a shared deal ID can be assigned to one of its two deals.

    Run: dbt show --select profile_shared_deal_ids_time_of_day

    Result (run 2026-10-21):
    | deal group                  | events | matching exactly one creation | unassigned |
    |-----------------------------|--------|-------------------------------|------------|
    | normal deals (one creation) | 15,326 | 15,326                        | 0          |
    | shared IDs (two creations)  |     80 |     80                        | 0          |

    Conclusion: in this dataset every event falls a whole number of days after its deal's
    creation, at the same time of day. That separates the two deals on each shared ID here, but
    nothing guarantees the pattern holds in other data, so the models don't split the IDs on it.

    Relied on by: the evidence for two deals per shared ID in int_deals; the decision not to split
    the shared IDs by time of day.
*/

with

changes as (

    select
        deal_id,
        changed_at
    from
        {{ ref('stg_pipedrive__deal_changes') }}

),

creations as (

    select
        deal_id,
        changed_at                              as created_at
    from
        {{ ref('stg_pipedrive__deal_changes') }}
    where
        changed_field_key = 'add_time'

),

deals as (

    select
        deal_id,
        has_multiple_creations
    from
        {{ ref('int_deal_creations_aggregated_to_deals') }}

),

-- per event: how many of its deal's creations share its time of day (0 = unassigned)
events_matched as (

    select
        changes.deal_id,
        changes.changed_at,
        count(creations.deal_id)                as matching_creations
    from
        changes
    left join creations
        on changes.deal_id = creations.deal_id
        and changes.changed_at::time = creations.created_at::time
    group by
        changes.deal_id,
        changes.changed_at

)

select
    case
        when deals.has_multiple_creations then 'shared IDs (two creations)'
        else 'normal deals (one creation)'
    end                                         as deal_group,
    count(*)                                    as events,
    count(*) filter (where events_matched.matching_creations = 1) as matching_exactly_one_creation,
    count(*) filter (where events_matched.matching_creations = 0) as unassigned
from
    events_matched
inner join deals
    on events_matched.deal_id = deals.deal_id
group by
    1
