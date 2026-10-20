/*
    Cumulative rule for stage steps: a deal that reached stage step N also reached every stage
    step below it, no later. Returns each deal and step that breaks this: a missing earlier step,
    or an earlier step reached after the later one. Any row fails the test.
    Only the whole-number stage steps ('1', '2', …) are checked; call steps ('2.1', '3.1') are not
    stage steps.
*/

with

stage_steps as (

    select
        deal_id,
        funnel_step::integer                    as step_number,
        entered_at
    from
        {{ ref('int_deal_funnel_steps_unioned') }}
    where
        funnel_step not like '%.%'

)

select
    later_step.deal_id,
    later_step.step_number                      as later_step_number,
    earlier_step.entered_at                     as earlier_step_entered_at,
    later_step.entered_at                       as later_step_entered_at
from
    stage_steps as later_step
left join stage_steps as earlier_step
    on later_step.deal_id = earlier_step.deal_id
    and earlier_step.step_number = later_step.step_number - 1
where
    later_step.step_number > 1
    and (
        earlier_step.deal_id is null
        or earlier_step.entered_at > later_step.entered_at
    )
