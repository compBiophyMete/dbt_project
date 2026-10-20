/*
    rep_sales_funnel_monthly counts every row of fct_deal_funnel_steps exactly once: per step, the
    report's total over all months equals the fact's rows for that step. Returns each step whose
    totals differ (e.g. a deal in a month outside the grid, or a step missing from the dimension);
    any row fails the test.
*/

with

report_totals as (

    select
        funnel_step,
        sum(deals_count)                        as report_deals
    from
        {{ ref('rep_sales_funnel_monthly') }}
    group by
        funnel_step

),

fact_totals as (

    select
        funnel_step,
        count(*)                                as fact_deals
    from
        {{ ref('fct_deal_funnel_steps') }}
    group by
        funnel_step

)

select
    coalesce(report_totals.funnel_step, fact_totals.funnel_step) as funnel_step,
    report_totals.report_deals,
    fact_totals.fact_deals
from
    report_totals
full outer join fact_totals
    on report_totals.funnel_step = fact_totals.funnel_step
where
    coalesce(report_totals.report_deals, 0) <> coalesce(fact_totals.fact_deals, 0)
