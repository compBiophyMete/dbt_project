with

funnel_steps as (

    select
        funnel_step,
        stage_id,
        activity_type,
        kpi_name
    from
        {{ ref('int_funnel_steps_mapped') }}

)

select
    funnel_step::varchar(10)                    as funnel_step,
    stage_id,
    activity_type::varchar(50)                  as activity_type,
    kpi_name::varchar(100)                      as kpi_name
from
    funnel_steps
