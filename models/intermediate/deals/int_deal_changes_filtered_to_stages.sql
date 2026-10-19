{# delete post_hook: see "Deletes" in int_deal_changes_filtered_to_stages.yml #}
{{
    config(
        post_hook="{{ delete_rows_missing_upstream(
            ref('stg_pipedrive__deal_changes'),
            ['deal_id', 'changed_at'],
            \"changed_field_key = 'stage_id'\"
        ) }}"
    )
}}

with

-- only the stage rows: a stage_id change moves the deal into the stage in new_value_integer
deal_changes as (

    select
        deal_id,
        new_value_integer,
        changed_at
    from
        {{ ref('stg_pipedrive__deal_changes') }}
    where
        changed_field_key = 'stage_id'
    {% if is_incremental() %}
        -- lookback for late-arriving stage changes: 2 days, 8 on Mondays (UTC). On changed_at, the
        -- raw change time, so the predicate is pushed through the staging view to the source
        and {{ incremental_lookback_filter('changed_at', default_days=2, weekly_days=8) }}
    {% endif %}

),

stage_changes as (

    select
        deal_id,
        new_value_integer                       as stage_id,
        changed_at
    from
        deal_changes

),

-- the lookback re-reads events that are already loaded; append only the ones that are new.
-- Matched on the raw (deal_id, changed_at), never on the derived stage_id
new_stage_changes as (

    select
        deal_id,
        stage_id,
        changed_at
    from
        stage_changes
    {% if is_incremental() %}
    where not exists (
        select 1
        from {{ this }} as existing
        where existing.changed_at = stage_changes.changed_at
            and existing.deal_id = stage_changes.deal_id
    )
    {% endif %}

)

-- no stage_name here: an appended row is never rewritten, so a stored name would go stale on a
-- rename; the name is joined downstream from stg_pipedrive__stages
select
    deal_id,
    stage_id,
    changed_at,
    -- start of the dbt run that appended this row
    cast('{{ run_started_at }}' as timestamp with time zone) as dwh_date
from
    new_stage_changes
