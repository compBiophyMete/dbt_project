/*
    Question: How many rows does each Pipedrive source table hold, over which dates, and how are
    the deal change-log rows split by changed field?

    Run: dbt show --select profile_source_overview --limit 20

    Result (run 2026-10-17):
    | source table   | detail                        | rows   | first date | last date  |
    |----------------|-------------------------------|--------|------------|------------|
    | activity       |                               |  4,579 | 2024-01-01 | 2024-09-13 |
    | activity_types |                               |      4 |            |            |
    | deal_changes   |                               | 15,406 | 2024-01-01 | 2025-03-11 |
    | deal_changes   | changed_field_key = add_time  |  2,000 | 2024-01-01 | 2024-09-13 |
    | deal_changes   | changed_field_key = lost_reason | 2,000 | 2024-02-11 | 2025-03-11 |
    | deal_changes   | changed_field_key = stage_id  |  8,906 | 2024-01-08 | 2025-02-24 |
    | deal_changes   | changed_field_key = user_id   |  2,500 | 2024-01-05 | 2024-11-02 |
    | fields         |                               |      4 |            |            |
    | stages         |                               |      9 |            |            |
    | users          |                               |  1,787 | 2024-01-02 | 2024-10-28 |
    (dates: `change_time` for deal_changes, `due_to` for activity, `modified` for users)

    Conclusion: the data covers January 2024 to March 2025. The deal change log is the largest
    table and the only source of deal history: creations, stage moves, owner changes and losses,
    each its own field key. Activities end in September 2024, six months before the change log.

    Relied on by: the four deal event models
    (int_deal_changes_filtered_to_creations, _stage_changes, _owner_changes, _losses); the report's month range.
*/

select
    'deal_changes'                              as source_table,
    null::text                                  as detail,
    count(*)                                    as row_count,
    min(change_time)::date                      as first_date,
    max(change_time)::date                      as last_date
from
    {{ source('pipedrive', 'deal_changes') }}

union all

select
    'deal_changes',
    'changed_field_key = ' || changed_field_key,
    count(*),
    min(change_time)::date,
    max(change_time)::date
from
    {{ source('pipedrive', 'deal_changes') }}
group by
    changed_field_key

union all

select
    'activity',
    null,
    count(*),
    min(due_to)::date,
    max(due_to)::date
from
    {{ source('pipedrive', 'activity') }}

union all

select 'activity_types', null, count(*), null, null from {{ source('pipedrive', 'activity_types') }}

union all

select 'fields', null, count(*), null, null from {{ source('pipedrive', 'fields') }}

union all

select 'stages', null, count(*), null, null from {{ source('pipedrive', 'stages') }}

union all

select
    'users',
    null,
    count(*),
    min(modified)::date,
    max(modified)::date
from
    {{ source('pipedrive', 'users') }}

order by
    1,
    2 nulls first
