/*
    Question: Per month, how many deals were created, and how many reached Lead Generation?

    Run: dbt show --select profile_creations_vs_lead_generation_by_month --limit 20

    Result (run 2026-10-21), the 5 shared deal IDs excluded; only months with a creation or a
    Lead Generation entry appear:
    | month   | created | reached Lead Generation |
    |---------|---------|-------------------------|
    | 2024-01 | 247     |  30                     |
    | 2024-02 | 204     | 194                     |
    | 2024-03 | 242     | 199                     |
    | 2024-04 | 243     | 229                     |
    | 2024-05 | 262     | 247                     |
    | 2024-06 | 246     | 244                     |
    | 2024-07 | 230     | 264                     |
    | 2024-08 | 225     | 238                     |
    | 2024-09 |  91     | 208                     |
    | 2024-10 |   0     | 119                     |
    | 2024-11 |   0     |  18                     |
    Both columns total 1,990.

    Conclusion: the same 1,990 deals, shifted by about a month: Lead Generation is dated by the
    stage-1 entry, which comes weeks after creation. January 2024 shows 30 leads although 247 deals
    were created, and leads continue into November 2024 after creations stop in September.

    Relied on by: the choice of stage-1 entry for Lead Generation and its documented lag in
    int_deal_funnel_steps_unioned and rep_sales_funnel_monthly.
*/

with

creations as (

    select
        date_trunc('month', created_at)::date   as month,
        count(*)                                as deals_created
    from
        {{ ref('int_deal_creations_aggregated_to_deals') }}
    where
        not has_multiple_creations
    group by
        date_trunc('month', created_at)::date

),

lead_generation as (

    select
        date_trunc('month', entered_at)::date   as month,
        count(*)                                as deals_reaching_lead_generation
    from
        {{ ref('int_deal_funnel_steps_unioned') }}
    where
        funnel_step = '1'
    group by
        date_trunc('month', entered_at)::date

)

-- every month with a creation or a Lead Generation entry: a full outer join keeps months that
-- appear on only one side
select
    coalesce(creations.month, lead_generation.month) as month,
    coalesce(creations.deals_created, 0)        as deals_created,
    coalesce(lead_generation.deals_reaching_lead_generation, 0) as deals_reaching_lead_generation
from
    creations
full outer join lead_generation
    on creations.month = lead_generation.month
order by
    month
