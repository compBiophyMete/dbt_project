{# delete post_hook: see "Deletes" in int_deal_changes_filtered_to_losses.yml #}
{{
    config(
        post_hook="{{ delete_rows_missing_upstream(
            ref('stg_pipedrive__deal_changes'),
            ['deal_id', 'changed_at'],
            \"changed_field_key = 'lost_reason'\"
        ) }}"
    )
}}

with

-- only the loss rows: a lost_reason change marks the deal lost with the reason in new_value_integer
deal_changes as (

    select
        deal_id,
        new_value_integer,
        changed_at
    from
        {{ ref('stg_pipedrive__deal_changes') }}
    where
        changed_field_key = 'lost_reason'
    {% if is_incremental() %}
        -- lookback for late-arriving losses: 2 days, 8 on Mondays (UTC). On changed_at, the raw
        -- change time, so the predicate is pushed through the staging view to the source
        and {{ incremental_lookback_filter('changed_at', default_days=2, weekly_days=8) }}
    {% endif %}

),

losses as (

    select
        deal_id,
        new_value_integer                       as lost_reason_id,
        changed_at
    from
        deal_changes

),

-- the lookback re-reads events that are already loaded; append only the ones that are new.
-- Matched on the raw (deal_id, changed_at), never on the derived lost_reason_id
new_losses as (

    select
        deal_id,
        lost_reason_id,
        changed_at
    from
        losses
    {% if is_incremental() %}
    where not exists (
        select 1
        from {{ this }} as existing
        where existing.changed_at = losses.changed_at
            and existing.deal_id = losses.deal_id
    )
    {% endif %}

)

-- no label here: an appended row is never rewritten, so a stored label would go stale on a rename;
-- the label is joined downstream from int_fields_unnested_to_options
select
    deal_id,
    lost_reason_id,
    changed_at,
    -- start of the dbt run that appended this row
    cast('{{ run_started_at }}' as timestamp with time zone) as dwh_date
from
    new_losses
