with

creations as (

    select
        deal_id,
        changed_at
    from
        {{ ref('int_deal_changes_filtered_to_creations') }}

),

-- stage changes and losses come from their facts, which already carry the current labels
stage_changes as (

    select
        deal_id,
        stage_id,
        stage_name,
        changed_at
    from
        {{ ref('fct_deal_stage_changes') }}

),

owner_changes as (

    select
        deal_id,
        owner_user_id,
        changed_at
    from
        {{ ref('int_deal_changes_filtered_to_owners') }}

),

losses as (

    select
        deal_id,
        lost_reason_id,
        lost_reason_name,
        lost_at                                 as changed_at
    from
        {{ ref('fct_deal_losses') }}

),

users as (

    select
        user_id,
        user_name
    from
        {{ ref('int_users') }}

),

-- the owner's current name, joined at build time. user_id is unique in int_users (n:1), so the
-- join never changes the row count
owner_changes_named as (

    select
        owner_changes.deal_id,
        owner_changes.owner_user_id,
        users.user_name                         as owner_name,
        owner_changes.changed_at
    from
        owner_changes
    left join users
        on owner_changes.owner_user_id = users.user_id

),

-- one timeline: each event type keeps its own row, never joined to another. Columns that don't
-- apply to an event type are null. union all: the inputs can't overlap (different event types)
events as (

    select
        deal_id,
        changed_at,
        'created'                               as event_type,
        null::integer                           as stage_id,
        null::text                              as stage_name,
        null::integer                           as owner_user_id,
        null::text                              as owner_name,
        null::integer                           as lost_reason_id,
        null::text                              as lost_reason_name
    from
        creations

    union all

    select
        deal_id,
        changed_at,
        'stage_changed'                         as event_type,
        stage_id,
        stage_name,
        null::integer                           as owner_user_id,
        null::text                              as owner_name,
        null::integer                           as lost_reason_id,
        null::text                              as lost_reason_name
    from
        stage_changes

    union all

    select
        deal_id,
        changed_at,
        'owner_changed'                         as event_type,
        null::integer                           as stage_id,
        null::text                              as stage_name,
        owner_user_id,
        owner_name,
        null::integer                           as lost_reason_id,
        null::text                              as lost_reason_name
    from
        owner_changes_named

    union all

    select
        deal_id,
        changed_at,
        'lost'                                  as event_type,
        null::integer                           as stage_id,
        null::text                              as stage_name,
        null::integer                           as owner_user_id,
        null::text                              as owner_name,
        lost_reason_id,
        lost_reason_name
    from
        losses

)

select
    deal_id,
    changed_at,
    event_type::varchar(20)                     as event_type,
    stage_id,
    stage_name::varchar(255)                    as stage_name,
    owner_user_id,
    owner_name::varchar(255)                    as owner_name,
    lost_reason_id,
    lost_reason_name::varchar(255)             as lost_reason_name
from
    events
