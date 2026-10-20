{# delete post_hook: see "Deletes" in int_deal_changes_filtered_to_owners.yml #}
{{
    config(
        post_hook="{{ delete_rows_missing_upstream(
            ref('stg_pipedrive__deal_changes'),
            ['deal_id', 'changed_at'],
            \"changed_field_key = 'user_id'\"
        ) }}"
    )
}}

with

-- only the owner rows: a user_id change hands the deal to the user in new_value_integer
deal_changes as (

    select
        deal_id,
        new_value_integer,
        changed_at
    from
        {{ ref('stg_pipedrive__deal_changes') }}
    where
        changed_field_key = 'user_id'
    {% if is_incremental() %}
        -- lookback for late-arriving owner changes: 2 days, 8 on Mondays (UTC). On changed_at, the
        -- raw change time, so the predicate is pushed through the staging view to the source
        and {{ incremental_lookback_filter('changed_at', default_days=2, weekly_days=8) }}
    {% endif %}

),

owner_changes as (

    select
        deal_id,
        new_value_integer                       as owner_user_id,
        changed_at
    from
        deal_changes

),

-- the lookback re-reads events that are already loaded; append only the ones that are new.
-- Matched on the raw (deal_id, changed_at), never on the derived owner_user_id
new_owner_changes as (

    select
        deal_id,
        owner_user_id,
        changed_at
    from
        owner_changes
    {% if is_incremental() %}
    where not exists (
        select 1
        from {{ this }} as existing
        where existing.changed_at = owner_changes.changed_at
            and existing.deal_id = owner_changes.deal_id
    )
    {% endif %}

)

select
    deal_id,
    owner_user_id,
    changed_at,
    -- start of the dbt run that appended this row
    cast('{{ run_started_at }}' as timestamp with time zone) as dwh_date
from
    new_owner_changes
