with

-- one row per deal and funnel step reached; all funnel rules are applied upstream
funnel_step_entries as (

    select
        funnel_step,
        entered_at
    from
        {{ ref('fct_deal_funnel_steps') }}

),

-- the closed list of steps, never the distinct steps seen in the fact: a step with no deals at
-- all must still get its rows
funnel_steps as (

    select
        funnel_step,
        kpi_name
    from
        {{ ref('dim_funnel_steps') }}

),

-- the report covers the whole data period, the first to the last month of any deal change or
-- activity, so months at the edges show 0 instead of disappearing
deal_events as (

    select
        min(changed_at)                         as first_at,
        max(changed_at)                         as last_at
    from
        {{ ref('fct_deal_events') }}

),

activities as (

    select
        min(due_at)                             as first_at,
        max(due_at)                             as last_at
    from
        {{ ref('fct_activities') }}

),

-- every month of the data period, generated here: from the month of the smallest available date
-- to the month of the largest. deal_events and activities hold one row each, so the cross join
-- yields one row for generate_series
months as (

    select
        generate_series(
            date_trunc('month', least(deal_events.first_at, activities.first_at)),
            date_trunc('month', greatest(deal_events.last_at, activities.last_at)),
            interval '1 month'
        )::date                                 as month
    from
        deal_events
    cross join activities

),

-- every month × every step
spine as (

    select
        months.month,
        funnel_steps.funnel_step,
        funnel_steps.kpi_name
    from
        months
    cross join funnel_steps

),

-- aggregate before joining: one row per month and step. count(*), not count(distinct deal_id):
-- the fact has one row per deal and step
monthly_counts as (

    select
        date_trunc('month', entered_at)::date   as month,
        funnel_step,
        count(*)                                as deals_count
    from
        funnel_step_entries
    group by
        date_trunc('month', entered_at)::date,
        funnel_step

)

select
    spine.month,
    spine.kpi_name,
    spine.funnel_step,
    coalesce(monthly_counts.deals_count, 0)::integer as deals_count
from
    spine
left join monthly_counts
    on spine.month = monthly_counts.month
    and spine.funnel_step = monthly_counts.funnel_step
