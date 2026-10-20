{{ config(severity='warn') }}

/*
    Early warning: a deal whose later creation row (not its first) has a creation time of exactly
    00:00:00 most likely had its "Deal created" date edited in Pipedrive, not a second deal created
    under its ID. Pipedrive lets users edit the day a deal was created, and an edited deal "will
    always show a creation time of 12:00 AM" (Pipedrive knowledge base:
    https://support.pipedrive.com/en/article/how-can-i-edit-the-deal-created-date).

    Why it matters: int_deals counts every extra creation row as a second deal
    (has_multiple_creations), and the funnel excludes such deals. An edited date would make a
    normal deal disappear from the funnel. Last known result:
    analyses/profile_edited_creation_dates.sql. A warning, not an error: the models don't treat edits
    separately yet, so a hit is a signal to review that deal, not a broken build.

    Returns each later creation row with a midnight creation time.
*/

with

creations as (

    select
        deal_id,
        created_at,
        changed_at,
        row_number() over (
            partition by deal_id
            order by changed_at
        )                                       as creation_rank
    from
        {{ ref('int_deal_changes_filtered_to_creations') }}

)

select
    deal_id,
    creation_rank,
    created_at,
    changed_at
from
    creations
where
    creation_rank > 1
    and created_at::time = '00:00:00'
