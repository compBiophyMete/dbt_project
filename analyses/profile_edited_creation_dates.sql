/*
    Question: Does any deal show signs of an edited creation date (a creation time of exactly
    00:00:00, or a creation value different from the time it was recorded)?

    Run: dbt show --select profile_edited_creation_dates

    Result (run 2026-10-17):
    | creation rows | later creation rows | at midnight | later at midnight | value ≠ change time |
    |---------------|---------------------|-------------|-------------------|---------------------|
    | 2,000         | 5                   | 0           | 0                 | 0                   |

    Conclusion: no creation date in this data was edited: no creation is at midnight (an edited
    creation date shows 12:00 AM in Pipedrive, see int_deals), and every creation value equals the
    time it was recorded. The 5 later creation rows (the shared deal IDs) are second deals, not
    edits. So `created_at` is the recorded creation timestamp for every deal today.

    Relied on by: the created_at limitation in int_deals, int_deal_changes_filtered_to_creations and the
    int_deals__created_at doc block; the warning test assert_no_edited_creation_dates.
*/

with

creations as (

    select
        deal_id,
        created_at,
        changed_at,
        row_number() over (
            partition by deal_id
            order by changed_at
        )                                       as creation_rank
    from
        {{ ref('int_deal_changes_filtered_to_creations') }}

)

select
    count(*)                                    as creation_rows,
    count(*) filter (where creation_rank > 1)   as later_creation_rows,
    count(*) filter (where created_at::time = '00:00:00') as at_midnight,
    count(*) filter (where creation_rank > 1 and created_at::time = '00:00:00') as later_at_midnight,
    count(*) filter (where created_at <> changed_at) as value_differs_from_change_time
from
    creations
