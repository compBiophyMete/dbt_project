{# delete post_hook: see "Deletes" in int_deal_changes_filtered_to_creations.yml #}
{{
    config(
        post_hook="{{ delete_rows_missing_upstream(
            ref('stg_pipedrive__deal_changes'),
            ['deal_id', 'changed_at'],
            \"changed_field_key = 'add_time'\"
        ) }}"
    )
}}

with

-- only the creation rows: add_time is the key whose value is the deal's creation timestamp
deal_changes as (

    select
        deal_id,
        new_value_timestamp,
        changed_at
    from
        {{ ref('stg_pipedrive__deal_changes') }}
    where
        changed_field_key = 'add_time'
    {% if is_incremental() %}
        -- lookback for late-arriving creations: 2 days, 8 on Mondays (UTC). On changed_at, the raw
        -- change time, so the predicate is pushed through the staging view to the source
        and {{ incremental_lookback_filter('changed_at', default_days=2, weekly_days=8) }}
    {% endif %}

),

creations as (

    select
        deal_id,
        new_value_timestamp                     as created_at,
        changed_at
    from
        deal_changes

),

-- the lookback re-reads events that are already loaded; append only the ones that are new.
-- Matched on the raw (deal_id, changed_at), never on the derived created_at: a null created_at
-- would never match, and the same row would be appended on every run
new_creations as (

    select
        deal_id,
        created_at,
        changed_at
    from
        creations
    {% if is_incremental() %}
    where not exists (
        select 1
        from {{ this }} as existing
        where existing.changed_at = creations.changed_at
            and existing.deal_id = creations.deal_id
    )
    {% endif %}

)

select
    deal_id,
    created_at,
    changed_at,
    -- start of the dbt run that appended this row
    cast('{{ run_started_at }}' as timestamp with time zone) as dwh_date
from
    new_creations
