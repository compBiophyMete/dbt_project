/*
    Question: In which stage are deals when they are lost?

    Run: dbt show --select profile_stage_at_loss --limit 10

    Result (run 2026-10-17), all 2,000 losses:
    | stage at loss                 | losses | share  |
    |-------------------------------|--------|--------|
    | 1 Lead Generation             |   5    |  0.3%  |
    | 2 Qualified Lead              |  40    |  2.0%  |
    | 3 Needs Assessment            |  89    |  4.5%  |
    | 4 Proposal/Quote Preparation  | 170    |  8.5%  |
    | 5 Negotiation                 | 270    | 13.5%  |
    | 6 Closing                     | 344    | 17.2%  |
    | 7 Implementation/Onboarding   | 357    | 17.9%  |
    | 8 Follow-up/Customer Success  | 400    | 20.0%  |
    | 9 Renewal/Expansion           | 325    | 16.3%  |

    Conclusion: most deals are lost late: 1,082 (54.1%) after Implementation/Onboarding (stages
    7–9), only 5 in Lead Generation. With no won status in the source, a deal onboarded and later
    lost (e.g. churned) counts as lost.

    Relied on by: int_deal_losses_joined_to_stages (stage at loss), fct_deal_losses, the "losses don't
    remove a deal from a step" rule in int_deal_funnel_steps_unioned (the 5 stage-1 losses).
*/

select
    losses.stage_id_at_loss,
    stages.stage_name,
    count(*)                                    as losses,
    round(100.0 * count(*) / sum(count(*)) over (), 1) as pct_of_losses
from
    {{ ref('int_deal_losses_joined_to_stages') }} as losses
inner join {{ ref('stg_pipedrive__stages') }} as stages
    on losses.stage_id_at_loss = stages.stage_id
group by
    losses.stage_id_at_loss,
    stages.stage_name
order by
    losses.stage_id_at_loss
