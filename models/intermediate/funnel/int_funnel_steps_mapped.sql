with

stages as (

    select
        stage_id,
        stage_name
    from
        {{ ref('stg_pipedrive__stages') }}

),

-- only the activity types that are funnel steps: Sales Call 1 (meeting), Sales Call 2 (sc_2)
activity_types as (

    select
        activity_type,
        activity_type_name
    from
        {{ ref('stg_pipedrive__activity_types') }}
    where
        activity_type in ('meeting', 'sc_2')

),

-- stage N is funnel step 'N' (text: call steps are '2.1' and '3.1'), named after the stage
stage_steps as (

    select
        stage_id::text                          as funnel_step,
        stage_id,
        null::text                              as activity_type,
        stage_name                              as kpi_name
    from
        stages

),

-- call steps: a closed mapping from activity type to funnel step, named after the activity type.
-- no else: an unmapped type gets a null step and fails the not_null test
call_steps as (

    select
        case
            when activity_type = 'meeting' then '2.1'
            when activity_type = 'sc_2' then '3.1'
        end                                     as funnel_step,
        null::integer                           as stage_id,
        activity_type,
        activity_type_name                      as kpi_name
    from
        activity_types

),

-- union all: stage steps and call steps never share a funnel_step
funnel_steps as (

    select
        funnel_step,
        stage_id,
        activity_type,
        kpi_name
    from
        stage_steps

    union all

    select
        funnel_step,
        stage_id,
        activity_type,
        kpi_name
    from
        call_steps

)

select
    funnel_step,
    stage_id,
    activity_type,
    kpi_name
from
    funnel_steps
