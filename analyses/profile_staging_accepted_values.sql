/*
    Question: Which distinct values do the categorical staging columns hold, to set the lists of
    their accepted_values tests?

    Run: dbt show --select profile_staging_accepted_values --limit 10

    Result (run 2026-10-20): 9 columns, 38 distinct values, no nulls.
    | model.column | distinct_values |
    |---|---|
    | stg_pipedrive__activities.activity_type | after_close_call, follow_up, meeting, sc_2 |
    | stg_pipedrive__activities.is_done | false, true |
    | stg_pipedrive__activity_types.activity_type_name | After Close Call, Follow Up Call, Sales Call 1, Sales Call 2 |
    | stg_pipedrive__activity_types.is_activity_type_active | false, true |
    | stg_pipedrive__deal_changes.changed_field_key | add_time, lost_reason, stage_id, user_id |
    | stg_pipedrive__deal_changes.new_value_integer (lost_reason rows) | 1, 2, 3, 4, 5 |
    | stg_pipedrive__fields.field_key | add_time, lost_reason, stage_id, user_id |
    | stg_pipedrive__fields.field_name | Deal Created, Lost Reason, Owner, Stage |
    | stg_pipedrive__stages.stage_name | Closing, Follow-up/Customer Success, Implementation/Onboarding, Lead Generation, Needs Assessment, Negotiation, Proposal/Quote Preparation, Qualified Lead, Renewal/Expansion |

    Conclusion: each column holds a small, closed set of values and no nulls, so each gets an
    accepted_values test whose list is exactly these values; a new value (a new activity type,
    field key, lost reason or stage) then fails the test and is reviewed before it is used.

    Relied on by: the accepted_values tests in stg_pipedrive__activities (activity_type, is_done),
    stg_pipedrive__activity_types (activity_type_name, is_activity_type_active),
    stg_pipedrive__deal_changes (changed_field_key, new_value_integer on lost_reason rows),
    stg_pipedrive__fields (field_key, field_name) and stg_pipedrive__stages (stage_name).
*/

with

-- one row per (model, column, value): select distinct, the same as running
-- `select distinct <column> from <model>` on each column
column_values as (

    select
        'stg_pipedrive__activities'             as model,
        'activity_type'                         as column_name,
        activity_type::text                     as value
    from
        {{ ref('stg_pipedrive__activities') }}

    union all

    select
        'stg_pipedrive__activities',
        'is_done',
        is_done::text
    from
        {{ ref('stg_pipedrive__activities') }}

    union all

    select
        'stg_pipedrive__activity_types',
        'activity_type_name',
        activity_type_name::text
    from
        {{ ref('stg_pipedrive__activity_types') }}

    union all

    select
        'stg_pipedrive__activity_types',
        'is_activity_type_active',
        is_activity_type_active::text
    from
        {{ ref('stg_pipedrive__activity_types') }}

    union all

    select
        'stg_pipedrive__deal_changes',
        'changed_field_key',
        changed_field_key::text
    from
        {{ ref('stg_pipedrive__deal_changes') }}

    union all

    -- only lost_reason rows: on the other keys new_value_integer is a stage or user ID
    select
        'stg_pipedrive__deal_changes',
        'new_value_integer (lost_reason rows)',
        new_value_integer::text
    from
        {{ ref('stg_pipedrive__deal_changes') }}
    where
        changed_field_key = 'lost_reason'

    union all

    select
        'stg_pipedrive__fields',
        'field_key',
        field_key::text
    from
        {{ ref('stg_pipedrive__fields') }}

    union all

    select
        'stg_pipedrive__fields',
        'field_name',
        field_name::text
    from
        {{ ref('stg_pipedrive__fields') }}

    union all

    select
        'stg_pipedrive__stages',
        'stage_name',
        stage_name::text
    from
        {{ ref('stg_pipedrive__stages') }}

)

-- one row per column, its distinct values in one comma-separated list
select
    model,
    column_name,
    string_agg(distinct coalesce(value, 'NULL'), ', ' order by coalesce(value, 'NULL')) as distinct_values
from
    column_values
group by
    model,
    column_name
order by
    model,
    column_name
