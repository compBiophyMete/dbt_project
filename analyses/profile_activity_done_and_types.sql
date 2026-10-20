/*
    Question: Per activity type, how many activities are done, and does the type's active flag
    vary between activities of the same type?

    Run: dbt show --select profile_activity_done_and_types --limit 10

    Result (run 2026-10-17):
    | type             | name             | rows  | done | done % | flag values per type | type active | due dates               |
    |------------------|------------------|-------|------|--------|----------------------|-------------|-------------------------|
    | after_close_call | After Close Call | 1,177 | 595  | 50.6   | 1                    | true        | 2024-01-01 – 2024-09-13 |
    | follow_up        | Follow Up Call   | 1,133 | 567  | 50.0   | 1                    | false       | 2024-01-01 – 2024-09-13 |
    | meeting          | Sales Call 1     | 1,145 | 568  | 49.6   | 1                    | true        | 2024-01-01 – 2024-09-13 |
    | sc_2             | Sales Call 2     | 1,124 | 560  | 49.8   | 1                    | true        | 2024-01-01 – 2024-09-13 |

    Conclusion: about half of every activity type is done. The type's active flag has one value
    per type, so it can't tell one activity from another: filtering on it would keep or drop whole
    types (it would remove every Sales Call 1 and 2). Done-ness is the per-activity column. All
    activities are due between January and September 2024.

    Relied on by: only done calls count, in int_activities_filtered_to_done; the decision not to filter on
    is_activity_type_active; the call steps 2.1 (568) and 3.1 (560) of int_deal_funnel_steps_unioned.
*/

select
    activity_type,
    activity_type_name,
    count(*)                                    as activity_rows,
    count(*) filter (where is_done)             as done_rows,
    round(100.0 * count(*) filter (where is_done) / count(*), 1) as done_pct,
    count(distinct is_activity_type_active)     as distinct_type_flag_values,
    bool_and(is_activity_type_active)           as type_is_active,
    min(due_at)::date                           as first_due,
    max(due_at)::date                           as last_due
from
    {{ ref('int_activities_joined_to_types') }}
group by
    activity_type,
    activity_type_name
order by
    activity_type
