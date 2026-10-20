/*
    Question: How many activities belong to a deal that has a history in the deal change log?

    Run: dbt show --select profile_activity_deal_linkage --limit 10

    Result (run 2026-10-17):
    | activity type    | rows  | distinct deals | rows with deal history | deals with deal history |
    |------------------|-------|----------------|------------------------|-------------------------|
    | after_close_call | 1,177 | 1,177          | 1                      | 1                       |
    | follow_up        | 1,133 | 1,133          | 3                      | 3                       |
    | meeting          | 1,145 | 1,145          | 2                      | 2                       |
    | sc_2             | 1,124 | 1,123          | 2                      | 2                       |
    | all types        | 4,579 | 4,572          | 8                      | 8                       |

    Conclusion: only 8 of 4,579 activity rows (8 of 4,572 deal IDs) belong to a deal with any
    history in the change log. Activities and deals barely share deal IDs, so activities can't be
    joined to deal stages: the call steps (2.1, 3.1) count their own population of deals.

    Relied on by: every deal with a done call counts in the call steps; the failing relationships tests on
    activity.deal_id (source and stg_pipedrive__activities, 4,571 rows); has_known_deal (int_activities_filtered_to_done,
    fct_activities); the call-step caveats in int_deal_funnel_steps_unioned and both reports.
*/

with

activity as (

    select
        activity_id,
        deal_id,
        activity_type
    from
        {{ ref('stg_pipedrive__activities') }}

),

-- every deal with any history in the change log
deal_list as (

    select distinct
        deal_id
    from
        {{ ref('stg_pipedrive__deal_changes') }}

),

activity_with_flag as (

    select
        activity.activity_id,
        activity.deal_id,
        activity.activity_type,
        exists (
            select 1
            from deal_list
            where deal_list.deal_id = activity.deal_id
        )                                       as has_deal_history
    from
        activity

)

select
    coalesce(activity_type, 'all types')        as activity_type,
    count(*)                                    as activity_rows,
    count(distinct deal_id)                     as distinct_deals,
    count(*) filter (where has_deal_history)    as rows_with_deal_history,
    count(distinct deal_id) filter (where has_deal_history) as deals_with_deal_history
from
    activity_with_flag
group by
    rollup (activity_type)
order by
    activity_type nulls last
