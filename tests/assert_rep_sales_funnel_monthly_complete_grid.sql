/*
    rep_sales_funnel_monthly holds every month × every funnel step. Returns one row when the
    report's row count differs from (months in the report) × (steps in dim_funnel_steps), or when
    a month in between is missing; any row fails the test.
*/

with

report as (

    select
        month
    from
        {{ ref('rep_sales_funnel_monthly') }}

),

expected as (

    select
        (
            -- whole months from the first to the last report month, both included
            (extract(year from age(max(report.month), min(report.month))) * 12
                + extract(month from age(max(report.month), min(report.month))) + 1)
            * (select count(*) from {{ ref('dim_funnel_steps') }})
        )::integer                              as expected_rows,
        count(*)                                as actual_rows
    from
        report

)

select
    expected_rows,
    actual_rows
from
    expected
where
    expected_rows <> actual_rows
